#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Idempotent macOS target generator. Safe to re-run after Xcode upgrades or
# when adding macOS/*.swift. Never modifies the iOS "Etherpad-iOS" target.

require "xcodeproj"
require "pathname"

TARGET_NAME       = "Etherpad-macOS"
BUNDLE_ID         = "com.humblebee.etherpad"
DEPLOYMENT_TARGET = "13.0"
SWIFT_VERSION     = "5.10"
DEVELOPMENT_TEAM  = "252N2WS4Y3"
FRAMEWORK_NAME    = "CsoundLib64.framework"
CSD_BASENAME      = "etherpad.csd"
IOS_TARGET_NAME   = "Etherpad-iOS"

PROJECT_DIR  = Pathname.new(File.expand_path("../..", __dir__))
PROJECT_PATH = PROJECT_DIR.join("Etherpad.xcodeproj").to_s
MACOS_DIR    = PROJECT_DIR.join("macOS")

abort("Cannot find #{PROJECT_PATH}") unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
log = ->(msg) { puts "  #{msg}" }
puts "==> Configuring #{TARGET_NAME}"

ios_target = project.targets.find { |t| t.name == IOS_TARGET_NAME }
abort("iOS target '#{IOS_TARGET_NAME}' not found — aborting") unless ios_target
ios_sources_before = ios_target.source_build_phase.files.map { |f| f.file_ref&.path }.compact.sort

target = project.targets.find { |t| t.name == TARGET_NAME }
if target.nil?
  target = project.new_target(:application, TARGET_NAME, :osx, DEPLOYMENT_TARGET)
  log.call("created application target")
else
  log.call("target exists — reconciling")
end

target.build_configurations.each do |config|
  bs = config.build_settings
  bs["PRODUCT_NAME"]               = "Etherpad"
  bs["PRODUCT_BUNDLE_IDENTIFIER"]  = BUNDLE_ID
  bs["MACOSX_DEPLOYMENT_TARGET"]   = DEPLOYMENT_TARGET
  bs["SDKROOT"]                    = "macosx"
  bs["SWIFT_VERSION"]              = SWIFT_VERSION
  bs["INFOPLIST_FILE"]             = "macOS/Info-macOS.plist"
  bs["GENERATE_INFOPLIST_FILE"]    = "NO"
  bs["SWIFT_OBJC_BRIDGING_HEADER"] = "macOS/Etherpad-macOS-Bridging-Header.h"
  bs["FRAMEWORK_SEARCH_PATHS"]     = ["$(inherited)", "$(PROJECT_DIR)/Frameworks"]
  bs["LD_RUNPATH_SEARCH_PATHS"]    = ["$(inherited)", "@executable_path/../Frameworks"]
  bs["DEVELOPMENT_TEAM"]           = DEVELOPMENT_TEAM
  bs["CODE_SIGN_STYLE"]            = "Automatic"
  bs["ENABLE_HARDENED_RUNTIME"]    = "YES"
  bs["ENABLE_USER_SCRIPT_SANDBOXING"] = "NO"
  bs["COMBINE_HIDPI_IMAGES"]       = "YES"
  bs["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  bs["CODE_SIGN_ENTITLEMENTS"]     = "macOS/Etherpad-macOS.entitlements"
  bs["CLANG_ENABLE_MODULES"]       = "YES"
end
log.call("build settings applied (bundle id #{BUNDLE_ID})")

group = project.main_group.find_subpath("macOS", true)
group.set_source_tree("SOURCE_ROOT")

def file_ref_for(project, group, abs_path)
  abs = Pathname.new(abs_path).realpath.to_s
  project.files.find { |f| (rp = (f.real_path rescue nil)) && rp.to_s == abs } || group.new_reference(abs_path)
end

swift_files = Dir.glob(MACOS_DIR.join("**", "*.swift")).reject { |p| p.include?("/project-setup/") }.sort
existing_src = target.source_build_phase.files.map { |f| (f.file_ref&.real_path rescue nil)&.to_s }.compact
swift_files.each do |path|
  ref = file_ref_for(project, group, path)
  next if existing_src.include?(Pathname.new(path).realpath.to_s)
  target.source_build_phase.add_file_reference(ref)
  log.call("source + #{Pathname.new(path).basename}")
end

[MACOS_DIR.join("Info-macOS.plist"),
 MACOS_DIR.join("Etherpad-macOS-Bridging-Header.h"),
 MACOS_DIR.join("Etherpad-macOS.entitlements")].each do |p|
  file_ref_for(project, group, p.to_s) if File.exist?(p)
end

assets = MACOS_DIR.join("Assets.xcassets").to_s
if File.exist?(assets)
  ref = file_ref_for(project, group, assets)
  target.resources_build_phase.add_file_reference(ref) unless target.resources_build_phase.files.any? { |f| f.file_ref == ref }
end

fw_abs = PROJECT_DIR.join("Frameworks", FRAMEWORK_NAME).to_s
abort("Missing #{FRAMEWORK_NAME} at #{fw_abs}") unless File.exist?(fw_abs)
fw_group = project.main_group.find_subpath("Frameworks", true)
fw_ref = file_ref_for(project, fw_group, fw_abs)
target.frameworks_build_phase.add_file_reference(fw_ref) unless target.frameworks_build_phase.files.any? { |f| f.file_ref == fw_ref }
embed = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
unless embed
  embed = target.new_copy_files_build_phase("Embed Frameworks")
  embed.symbol_dst_subfolder_spec = :frameworks
end
unless embed.files.any? { |f| f.file_ref == fw_ref }
  bf = embed.add_file_reference(fw_ref)
  bf.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
end
log.call("framework linked + embedded")

# Embed & Sign skips nested dylibs in CsoundLib64.framework/Versions/Current/libs;
# hardened runtime rejects them unless re-signed with the build identity.
SIGN_PHASE = "Sign embedded Csound libraries"
unless target.shell_script_build_phases.any? { |p| p.name == SIGN_PHASE }
  phase = target.new_shell_script_build_phase(SIGN_PHASE)
  phase.shell_path = "/bin/sh"
  phase.always_out_of_date = "1"
  phase.shell_script = <<~SH
    set -e
    [ "${CODE_SIGNING_ALLOWED}" = "YES" ] || exit 0
    [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ] || exit 0
    FW="${CODESIGNING_FOLDER_PATH}/Contents/Frameworks/CsoundLib64.framework"
    [ -d "$FW" ] || exit 0
    for dylib in "$FW/Versions/Current/libs"/*.dylib; do
      [ -f "$dylib" ] || continue
      codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --options runtime "$dylib"
    done
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --options runtime "$FW/Versions/Current/CsoundLib64"
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --options runtime "$FW"
  SH
  log.call("added signing phase")
end

DSYM_PHASE = "Generate Csound dSYMs"
unless target.shell_script_build_phases.any? { |p| p.name == DSYM_PHASE }
  phase = target.new_shell_script_build_phase(DSYM_PHASE)
  phase.shell_path = "/bin/sh"
  phase.always_out_of_date = "1"
  phase.shell_script = <<~SH
    set -e
    [ "${ACTION}" = "install" ] || exit 0
    [ "${CONFIGURATION}" = "Release" ] || exit 0
    FW="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/CsoundLib64.framework"
    [ -d "$FW" ] || exit 0
    OUT="${DWARF_DSYM_FOLDER_PATH}"
    MAIN="${FW}/Versions/Current/CsoundLib64"
    if [ -f "$MAIN" ]; then
      dsymutil "$MAIN" -o "${OUT}/CsoundLib64.framework.dSYM"
    fi
    for dylib in "${FW}/Versions/Current/libs/"*.dylib; do
      [ -f "$dylib" ] || continue
      dsymutil "$dylib" -o "${OUT}/$(basename "$dylib").dSYM"
    done
  SH
  log.call("added dSYM generation phase")
end

csd_ref = project.files.find { |f| (f.path || "").end_with?("macOS/#{CSD_BASENAME}") }
abort("Could not find macOS/#{CSD_BASENAME} reference") unless csd_ref
unless target.resources_build_phase.files.any? { |f| f.file_ref == csd_ref }
  target.resources_build_phase.add_file_reference(csd_ref)
  log.call("added macOS #{CSD_BASENAME}")
end

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(PROJECT_PATH, TARGET_NAME, true)
log.call("wrote shared scheme")

if ios_target.source_build_phase.files.map { |f| f.file_ref&.path }.compact.sort != ios_sources_before
  abort("REFUSING TO SAVE: iOS target membership changed")
end

project.save

# xcodeproj 1.25.0 drops preferredProjectObjectVersion; restore for Xcode 16+.
pbx_path = PROJECT_PATH + "/project.pbxproj"
pbx = File.read(pbx_path)
unless pbx.include?("preferredProjectObjectVersion")
  marker = "\t\t\tisa = PBXProject;\n"
  patched = pbx.sub(marker, marker + "\t\t\tpreferredProjectObjectVersion = 77;\n")
  File.write(pbx_path, patched) if patched != pbx
end

puts "==> Done. iOS sources untouched (#{ios_sources_before.length}); macOS sources (#{swift_files.length})."
