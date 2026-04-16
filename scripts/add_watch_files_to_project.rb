#!/usr/bin/env ruby
#
# Add Watch-related source files to the Xcode project and link WatchConnectivity.
#
require 'xcodeproj'

project_path = File.join(__dir__, '..', 'RemoteShutter.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Find the main iOS target
ios_target = project.targets.find { |t| t.name == 'RemoteShutter' }
raise 'Could not find RemoteShutter target' unless ios_target

# Find or create the RemoteCam group (where iOS source files live)
remotecam_group = project.main_group.find_subpath('RemoteCam', true)

# Find or create the Shared group
shared_group = project.main_group.find_subpath('Shared', true)
shared_group.set_source_tree('SOURCE_ROOT')
shared_group.set_path('Shared')

# ---- Add new iOS source files to RemoteCam group and iOS target ----

ios_new_files = [
  'RemoteCam/WatchSessionManager.swift',
  'RemoteCam/WatchRemoteCameraController.swift',
  'RemoteCam/WatchRemoteCamStates.swift',
]

ios_new_files.each do |rel_path|
  filename = File.basename(rel_path)
  # Skip if already in project
  existing = remotecam_group.files.find { |f| f.display_name == filename }
  if existing
    puts "Already in project: #{filename}"
    next
  end

  file_ref = remotecam_group.new_reference(filename)
  file_ref.set_source_tree('SOURCE_ROOT')
  file_ref.set_path(rel_path)
  ios_target.source_build_phase.add_file_reference(file_ref)
  puts "Added to iOS target: #{filename}"
end

# ---- Add shared file to both iOS and (future) Watch target ----

shared_files = ['Shared/WatchSharedTypes.swift']

shared_files.each do |rel_path|
  filename = File.basename(rel_path)
  existing = shared_group.files.find { |f| f.display_name == filename }
  if existing
    puts "Already in project: #{filename}"
    next
  end

  file_ref = shared_group.new_reference(filename)
  file_ref.set_source_tree('SOURCE_ROOT')
  file_ref.set_path(rel_path)
  ios_target.source_build_phase.add_file_reference(file_ref)
  puts "Added to iOS target: #{filename}"
end

# ---- Link WatchConnectivity framework to iOS target ----

wc_framework = 'WatchConnectivity.framework'
already_linked = ios_target.frameworks_build_phase.files.any? { |f|
  f.display_name == wc_framework
}

unless already_linked
  framework_ref = project.frameworks_group.new_reference(wc_framework)
  framework_ref.set_source_tree('SDKROOT')
  framework_ref.set_path("System/Library/Frameworks/#{wc_framework}")
  ios_target.frameworks_build_phase.add_file_reference(framework_ref)
  puts "Linked framework: #{wc_framework}"
end

# ---- Save ----
project.save
puts 'Project saved successfully.'
