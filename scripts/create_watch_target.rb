#!/usr/bin/env ruby
#
# Creates the RemoteShutterWatch watchOS app target in the Xcode project.
#
require 'xcodeproj'

project_path = 'RemoteShutter.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if target already exists
if project.targets.any? { |t| t.name == 'RemoteShutterWatch' }
  puts 'RemoteShutterWatch target already exists, skipping creation.'
  exit 0
end

ios_target = project.targets.find { |t| t.name == 'RemoteShutter' }

# ---- Create watchOS app target ----
watch_target = project.new_target(
  :application,
  'RemoteShutterWatch',
  :watchos,
  '10.0'
)
watch_target.product_name = 'RemoteShutterWatch'

# Set bundle identifier and build settings
watch_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.securityunion.RemoteShutter.watchkitapp'
  config.build_settings['INFOPLIST_FILE'] = 'RemoteShutterWatch/Info.plist'
  config.build_settings['SDKROOT'] = 'watchos'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4' # Watch
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '1.0'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
end

# ---- Create/find the RemoteShutterWatch group ----
watch_group = project.main_group.find_subpath('RemoteShutterWatch', true)
watch_group.set_source_tree('SOURCE_ROOT')
watch_group.set_path('RemoteShutterWatch')

# ---- Add Watch Swift source files ----
watch_files = [
  'RemoteShutterWatchApp.swift',
  'WatchSessionDelegate.swift',
  'WatchCameraViewModel.swift',
  'WatchControlView.swift',
  'WatchConnectionView.swift',
]

watch_files.each do |filename|
  existing = watch_group.files.find { |f| f.display_name == filename }
  if existing
    puts "Already in project: #{filename}"
    # Make sure it's in the build phase
    unless watch_target.source_build_phase.files.any? { |f| f.file_ref == existing }
      watch_target.source_build_phase.add_file_reference(existing)
    end
    next
  end

  file_ref = watch_group.new_reference(filename)
  file_ref.set_source_tree('SOURCE_ROOT')
  file_ref.set_path("RemoteShutterWatch/#{filename}")
  watch_target.source_build_phase.add_file_reference(file_ref)
  puts "Added to Watch target: #{filename}"
end

# ---- Add shared files to Watch target ----
shared_group = project.main_group.find_subpath('Shared', true)

shared_files_to_add = ['WatchSharedTypes.swift']
shared_files_to_add.each do |filename|
  file_ref = shared_group.files.find { |f| f.display_name == filename }
  if file_ref
    unless watch_target.source_build_phase.files.any? { |f| f.file_ref == file_ref }
      watch_target.source_build_phase.add_file_reference(file_ref)
      puts "Added shared file to Watch target: #{filename}"
    end
  else
    puts "WARNING: #{filename} not found in Shared group"
  end
end

# ---- Add FlatBufferSchemas_generated.swift to Watch target ----
remotecam_group = project.main_group.find_subpath('RemoteCam', true)
generated_ref = remotecam_group.files.find { |f| f.display_name == 'FlatBufferSchemas_generated.swift' }
if generated_ref
  unless watch_target.source_build_phase.files.any? { |f| f.file_ref == generated_ref }
    watch_target.source_build_phase.add_file_reference(generated_ref)
    puts "Added FlatBufferSchemas_generated.swift to Watch target"
  end
end

# ---- Link WatchConnectivity framework ----
wc_framework = 'WatchConnectivity.framework'
framework_ref = project.frameworks_group.new_reference(wc_framework)
framework_ref.set_source_tree('SDKROOT')
framework_ref.set_path("System/Library/Frameworks/#{wc_framework}")
watch_target.frameworks_build_phase.add_file_reference(framework_ref)
puts "Linked #{wc_framework} to Watch target"

# ---- Set the Watch app as a dependency of the iOS app ----
ios_target.add_dependency(watch_target)
puts "Added Watch target as dependency of iOS target"

# ---- Save ----
project.save
puts 'Watch target created successfully!'
