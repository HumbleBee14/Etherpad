#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Idempotent AUv3 extension target generator for iPad/iOS.
# Safe to re-run. Does not modify macOS or iOS app source membership beyond embed + dependency.

require "xcodeproj"
require "pathname"

TARGET_NAME       = "Etherpad-AU"
CONTAINER_TARGET  = "Etherpad-iOS"
BUNDLE_ID         = "com.humblebee.etherpad.EtherpadAU"
DEPLOYMENT_TARGET = "17.0"
SWIFT_VERSION     = "5.10"
DEVELOPMENT_TEAM  = "252N2WS4Y3"
CSD_BASENAME      = "etherpad.csd"

PROJECT_DIR  = Pathname.new(File.expand_path("../..", __dir__))
PROJECT_PATH = PROJECT_DIR.join("Etherpad.xcodeproj").to_s
AU_DIR       = PROJECT_DIR.join("AU")
IOS_DIR      = PROJECT_DIR.join("iOS")

abort("Cannot find #{PROJECT_PATH}") unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
# xcodeproj gem caps at object version 63; strip 77 so save succeeds (restore after).
pbx_path = PROJECT_PATH + "/project.pbxproj"
pbx_raw = File.read(pbx_path)
pbx_stripped = pbx_raw.gsub(/\t\t\tpreferredProjectObjectVersion = 77;\n/, "")
File.write(pbx_path, pbx_stripped) if pbx_stripped != pbx_raw
project = Xcodeproj::Project.open(PROJECT_PATH) if pbx_stripped != pbx_raw
log = ->(msg) { puts "  #{msg}" }
puts "==> Configuring #{TARGET_NAME}"

ios_target = project.targets.find { |t| t.name == CONTAINER_TARGET }
abort("Container target '#{CONTAINER_TARGET}' not found") unless ios_target

target = project.targets.find { |t| t.name == TARGET_NAME }
if target.nil?
  target = project.new_target(:app_extension, TARGET_NAME, :ios, DEPLOYMENT_TARGET)
  log.call("created app extension target")
else
  log.call("target exists — reconciling")
end

target.build_configurations.each do |config|
  bs = config.build_settings
  bs["PRODUCT_NAME"]                  = "EtherpadAU"
  bs["PRODUCT_BUNDLE_IDENTIFIER"]     = BUNDLE_ID
  bs["IPHONEOS_DEPLOYMENT_TARGET"]    = DEPLOYMENT_TARGET
  bs["SDKROOT"]                       = "iphoneos"
  bs["SWIFT_VERSION"]                 = SWIFT_VERSION
  bs["INFOPLIST_FILE"]                = "AU/Info.plist"
  bs["GENERATE_INFOPLIST_FILE"]       = "NO"
  bs["SWIFT_OBJC_BRIDGING_HEADER"]    = "AU/Etherpad-AU-Bridging-Header.h"
  bs["FRAMEWORK_SEARCH_PATHS"]        = ["$(inherited)", "$(PROJECT_DIR)/Frameworks"]
  bs["HEADER_SEARCH_PATHS"]           = [
    "$(inherited)",
    "$(PROJECT_DIR)/Frameworks/CsoundiOS.xcframework/ios-arm64/Headers",
    "$(PROJECT_DIR)/Frameworks/CsoundiOS.xcframework/ios-arm64-simulator/Headers",
    "$(PROJECT_DIR)/iOS/Headers",
  ]
  bs["LD_RUNPATH_SEARCH_PATHS"]       = ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
  bs["DEVELOPMENT_TEAM"]              = DEVELOPMENT_TEAM
  bs["CODE_SIGN_STYLE"]               = "Automatic"
  bs["ENABLE_BITCODE"]                = "NO"
  bs["CLANG_ENABLE_MODULES"]          = "YES"
  bs["MARKETING_VERSION"]             = "1.2"
  bs["CURRENT_PROJECT_VERSION"]       = "1"
  bs["SKIP_INSTALL"]                  = "YES"
  bs["APPLICATION_EXTENSION_API_ONLY"] = "YES"
  bs["TARGETED_DEVICE_FAMILY"]        = "1,2"
  bs["OTHER_LDFLAGS"]                 = ["$(inherited)", "-framework", "Accelerate"]
end
log.call("build settings applied (#{BUNDLE_ID})")

au_group = project.main_group.find_subpath("AU", true)
au_group.set_source_tree("SOURCE_ROOT")
unless project.main_group.children.any? { |c| c.display_name == "AU" }
  project.main_group.children << au_group
end

def file_ref_for(project, group, abs_path)
  abs = Pathname.new(abs_path).realpath.to_s
  project.files.find { |f| (rp = (f.real_path rescue nil)) && rp.to_s == abs } || group.new_reference(abs_path)
end

au_swift = Dir.glob(AU_DIR.join("*.swift")).sort
shared_swift = Dir.glob(IOS_DIR.join("Shared", "*.swift")).sort
au_engine_swift = [
  IOS_DIR.join("Engine/HostCsoundEngine.swift"),
  IOS_DIR.join("Views/TouchSurfaceView.swift"),
  IOS_DIR.join("Views/VisualEffects.swift"),
].select { |p| File.exist?(p) }

au_sources = (au_swift + shared_swift + au_engine_swift).map { |p| Pathname.new(p).realpath.to_s }.uniq.sort
ios_shared_only = shared_swift.map { |p| Pathname.new(p).realpath.to_s }.uniq.sort

def add_sources(project, target, paths, au_group, log)
  existing = target.source_build_phase.files.map { |f| (f.file_ref&.real_path rescue nil)&.to_s }.compact
  paths.each do |path|
    group = if path.include?("/AU/")
              au_group
            elsif path.include?("/Shared/")
              project.main_group.find_subpath("iOS/Shared", true)
            else
              project.main_group.find_subpath("iOS", true)
            end
    ref = file_ref_for(project, group, path)
    next if existing.include?(path)
    target.source_build_phase.add_file_reference(ref)
    log.call("#{target.name} source + #{Pathname.new(path).basename}")
  end
end

add_sources(project, target, au_sources, au_group, log)
add_sources(project, ios_target, ios_shared_only, au_group, log)

# Remove HostCsoundEngine from iOS app if present (AU-only backend).
ios_target.source_build_phase.files.reject! do |bf|
  path = (bf.file_ref&.real_path rescue nil)&.to_s
  if path&.end_with?("HostCsoundEngine.swift")
    log.call("removed HostCsoundEngine from #{CONTAINER_TARGET}")
    true
  else
    false
  end
end

[AU_DIR.join("Info.plist").to_s,
 AU_DIR.join("Etherpad-AU-Bridging-Header.h").to_s].each do |p|
  file_ref_for(project, au_group, p) if File.exist?(p)
end

fw_group = project.main_group.find_subpath("Frameworks", true)
%w[CsoundiOS.xcframework libSndfileiOS.xcframework].each do |fw|
  fw_abs = PROJECT_DIR.join("Frameworks", fw).to_s
  abort("Missing #{fw}") unless File.exist?(fw_abs)
  fw_ref = file_ref_for(project, fw_group, fw_abs)
  target.frameworks_build_phase.add_file_reference(fw_ref) unless target.frameworks_build_phase.files.any? { |f| f.file_ref == fw_ref }
  log.call("linked #{fw}")
end

csd_ref = project.files.find { |f| f.uuid == "2AAFC2E3511EC1E15B11152C" }
csd_ref ||= project.files.find do |f|
  (f.path || "") == CSD_BASENAME && !(f.real_path.to_s.include?("macOS") rescue true)
end
abort("Could not find iOS #{CSD_BASENAME} reference") unless csd_ref
unless target.resources_build_phase.files.any? { |f| f.file_ref == csd_ref }
  target.resources_build_phase.add_file_reference(csd_ref)
  log.call("resource + #{CSD_BASENAME}")
end

# Embed extension in container app.
embed = ios_target.copy_files_build_phases.find { |p| p.name == "Embed Foundation Extensions" }
unless embed
  embed = ios_target.new_copy_files_build_phase("Embed Foundation Extensions")
  embed.dst_subfolder_spec = "13" # PlugIns
end
appex_ref = target.product_reference
unless embed.files.any? { |f| f.file_ref == appex_ref }
  bf = embed.add_file_reference(appex_ref)
  bf.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
  log.call("embedded AU in #{CONTAINER_TARGET}")
end

unless ios_target.dependencies.any? { |d| d.target == target }
  dep = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  dep.target = target
  ios_target.dependencies << dep
  log.call("container depends on #{TARGET_NAME}")
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(ios_target)
scheme.save_as(PROJECT_PATH, TARGET_NAME, true)
log.call("wrote shared scheme #{TARGET_NAME}")

project.save

pbx = File.read(pbx_path)
unless pbx.include?("preferredProjectObjectVersion")
  marker = "\t\t\tisa = PBXProject;\n"
  patched = pbx.sub(marker, marker + "\t\t\tpreferredProjectObjectVersion = 77;\n")
  File.write(pbx_path, patched) if patched != pbx
end

puts "==> Done. Build #{TARGET_NAME}, run #{CONTAINER_TARGET}, open in GarageBand iPad to test."
