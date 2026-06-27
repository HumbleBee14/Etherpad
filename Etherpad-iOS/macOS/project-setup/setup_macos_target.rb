#!/usr/bin/env ruby
# frozen_string_literal: true
#
# setup_macos_target.rb — idempotent generator for the native macOS app target.
# ----------------------------------------------------------------------------
# WHY THIS EXISTS
#   The "Etherpad-macOS" target is created/configured by THIS SCRIPT rather than
#   by hand-editing project.pbxproj or clicking through Xcode. That makes the
#   target reproducible: after an Xcode upgrade, on a fresh clone, or if the
#   project file is ever regenerated, just re-run this script to recreate the
#   exact same target. It is fully IDEMPOTENT — running it again reconciles the
#   existing target (by name/path) instead of injecting duplicate targets, build
#   files, framework links, or schemes.
#
# WHAT IT GUARANTEES (the project-structure contract)
#   * ONE project (Etherpad.xcodeproj), TWO targets: existing iOS "Etherpad"
#     (UNTOUCHED) + new "Etherpad-macOS".
#   * The macOS target compiles ONLY macOS/*.swift. No iOS source is added to it,
#     and no iOS target membership is modified.
#   * SAME bundle id as iOS (com.humblebee.etherpad) -> Universal Purchase / one
#     App Store Connect record / one pipeline.
#   * The ONLY shared artifact is Etherpad/Resources/etherpad.csd, added to the
#     macOS target's resources by REUSING the existing iOS file reference (still
#     one file on disk, one ref in the project).
#   * CsoundLib64.framework (vendored, macOS Csound 6.18.1, double) is linked and
#     embedded (Embed & Sign) into the macOS target only.
#
# USAGE
#   cd Etherpad-iOS/macOS/project-setup && ruby setup_macos_target.rb
#   (re-run any time after adding new macOS/*.swift files to sync membership.)

require "xcodeproj"
require "pathname"

# ---- Constants (the structure contract) ------------------------------------
TARGET_NAME       = "Etherpad-macOS"
BUNDLE_ID         = "com.humblebee.etherpad"   # MUST equal the iOS target's id
DEPLOYMENT_TARGET = "13.0"
SWIFT_VERSION     = "5.10"
DEVELOPMENT_TEAM  = "252N2WS4Y3"
FRAMEWORK_NAME    = "CsoundLib64.framework"
CSD_BASENAME      = "etherpad.csd"
IOS_TARGET_NAME   = "Etherpad"

# project dir = Etherpad-iOS/ (two levels up from macOS/project-setup/)
PROJECT_DIR  = Pathname.new(File.expand_path("../..", __dir__))
PROJECT_PATH = PROJECT_DIR.join("Etherpad.xcodeproj").to_s
MACOS_DIR    = PROJECT_DIR.join("macOS")

abort("Cannot find #{PROJECT_PATH}") unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
log = ->(msg) { puts "  #{msg}" }
puts "==> Configuring #{TARGET_NAME} in #{PROJECT_PATH}"

# ---- Guard: never mutate the iOS target ------------------------------------
ios_target = project.targets.find { |t| t.name == IOS_TARGET_NAME }
abort("iOS target '#{IOS_TARGET_NAME}' not found — aborting to avoid corrupting project") unless ios_target
ios_sources_before = ios_target.source_build_phase.files.map { |f| f.file_ref&.path }.compact.sort

# ---- 1. Target (create once, else reuse) -----------------------------------
target = project.targets.find { |t| t.name == TARGET_NAME }
if target.nil?
  target = project.new_target(:application, TARGET_NAME, :osx, DEPLOYMENT_TARGET)
  log.call("created application target")
else
  log.call("target already exists — reconciling")
end

# ---- 2. Build settings (overwrite => idempotent) ---------------------------
target.build_configurations.each do |config|
  bs = config.build_settings
  bs["PRODUCT_NAME"]                 = "Etherpad"            # ships as Etherpad.app
  bs["PRODUCT_BUNDLE_IDENTIFIER"]    = BUNDLE_ID
  bs["MACOSX_DEPLOYMENT_TARGET"]     = DEPLOYMENT_TARGET
  bs["SDKROOT"]                      = "macosx"
  bs["SWIFT_VERSION"]                = SWIFT_VERSION
  bs["INFOPLIST_FILE"]               = "macOS/Info-macOS.plist"
  bs["GENERATE_INFOPLIST_FILE"]      = "NO"
  bs["SWIFT_OBJC_BRIDGING_HEADER"]   = "macOS/Etherpad-macOS-Bridging-Header.h"
  bs["FRAMEWORK_SEARCH_PATHS"]       = ["$(inherited)", "$(PROJECT_DIR)"]
  bs["LD_RUNPATH_SEARCH_PATHS"]      = ["$(inherited)", "@executable_path/../Frameworks"]
  bs["DEVELOPMENT_TEAM"]             = DEVELOPMENT_TEAM
  bs["CODE_SIGN_STYLE"]              = "Automatic"
  bs["ENABLE_HARDENED_RUNTIME"]      = "YES"
  bs["COMBINE_HIDPI_IMAGES"]         = "YES"
  bs["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""             # no asset catalog yet
  bs["CLANG_ENABLE_MODULES"]         = "YES"
end
log.call("applied build settings (bundle id #{BUNDLE_ID}, macOS #{DEPLOYMENT_TARGET})")

# ---- group for macOS files (source tree = SOURCE_ROOT, i.e. PROJECT_DIR) ----
group = project.main_group.find_subpath("macOS", true)
group.set_source_tree("SOURCE_ROOT")

# helper: find-or-create a file reference (deduped by absolute real path)
def file_ref_for(project, group, abs_path)
  abs = Pathname.new(abs_path).realpath.to_s
  existing = project.files.find { |f| (rp = (f.real_path rescue nil)) && rp.to_s == abs }
  existing || group.new_reference(abs_path)
end

# ---- 3. Swift sources: add every macOS/*.swift (excluding this tool dir) ----
swift_files = Dir.glob(MACOS_DIR.join("**", "*.swift")).reject { |p| p.include?("/project-setup/") }.sort
existing_src = target.source_build_phase.files.map { |f| (f.file_ref&.real_path rescue nil)&.to_s }.compact
swift_files.each do |path|
  ref = file_ref_for(project, group, path)
  next if existing_src.include?(Pathname.new(path).realpath.to_s)
  target.source_build_phase.add_file_reference(ref)
  log.call("source + #{Pathname.new(path).basename}")
end

# ---- 4. Non-compiled macOS files visible in the project (no build phase) ----
[MACOS_DIR.join("Info-macOS.plist"), MACOS_DIR.join("Etherpad-macOS-Bridging-Header.h")].each do |p|
  file_ref_for(project, group, p.to_s) if File.exist?(p)
end

# ---- 5. Link + embed CsoundLib64.framework (macOS target only) -------------
fw_abs = PROJECT_DIR.join(FRAMEWORK_NAME).to_s
abort("Missing vendored #{FRAMEWORK_NAME} at #{fw_abs}") unless File.exist?(fw_abs)
fw_group = project.main_group.find_subpath("Frameworks", true)
fw_ref = file_ref_for(project, fw_group, fw_abs)

linked = target.frameworks_build_phase.files.any? { |f| f.file_ref == fw_ref }
target.frameworks_build_phase.add_file_reference(fw_ref) unless linked
log.call(linked ? "framework already linked" : "framework linked")

embed = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
unless embed
  embed = target.new_copy_files_build_phase("Embed Frameworks")
  embed.symbol_dst_subfolder_spec = :frameworks
end
unless embed.files.any? { |f| f.file_ref == fw_ref }
  bf = embed.add_file_reference(fw_ref)
  bf.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
  log.call("framework embedded (Embed & Sign)")
end

# ---- 6. Shared resource: etherpad.csd (reuse existing iOS file ref) --------
csd_ref = project.files.find { |f| f.path && File.basename(f.path) == CSD_BASENAME }
abort("Could not find #{CSD_BASENAME} reference in project") unless csd_ref
unless target.resources_build_phase.files.any? { |f| f.file_ref == csd_ref }
  target.resources_build_phase.add_file_reference(csd_ref)
  log.call("added shared #{CSD_BASENAME} to resources")
end

# ---- 7. Shared scheme (so `xcodebuild -scheme Etherpad-macOS` + CI work) ----
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(PROJECT_PATH, TARGET_NAME, true)
log.call("wrote shared scheme #{TARGET_NAME}")

# ---- Guard: assert iOS target membership is byte-for-byte unchanged ---------
ios_sources_after = ios_target.source_build_phase.files.map { |f| f.file_ref&.path }.compact.sort
if ios_sources_before != ios_sources_after
  abort("REFUSING TO SAVE: iOS target source membership changed — that violates the no-iOS-edits contract.")
end

project.save

# ---- 8. Post-save: restore Xcode-16+ project attributes that xcodeproj 1.25.0
# (which models up to objectVersion 63) silently drops on save. Without this,
# Xcode re-injects `preferredProjectObjectVersion` on its next save, producing
# surprise churn in a later commit. Re-adding it here keeps the pbxproj
# byte-stable whether it was last written by this script or by Xcode.
# Idempotent: only inserts when absent. The actual format (`objectVersion = 77`)
# is preserved by xcodeproj, so Xcode opens the project unchanged.
pbx = File.read(PROJECT_PATH + "/project.pbxproj")
unless pbx.include?("preferredProjectObjectVersion")
  marker = "\t\t\tisa = PBXProject;\n"
  patched = pbx.sub(marker, marker + "\t\t\tpreferredProjectObjectVersion = 77;\n")
  if patched != pbx
    File.write(PROJECT_PATH + "/project.pbxproj", patched)
    log.call("restored preferredProjectObjectVersion = 77")
  else
    warn "  WARN: could not find PBXProject marker to restore preferredProjectObjectVersion"
  end
end

puts "==> Done. iOS target untouched (#{ios_sources_after.length} sources). macOS sources: #{swift_files.length}."
