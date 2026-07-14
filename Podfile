# Uncomment this line to define a global platform for your project
# platform :ios, '6.0'
# pod trunk push Theater.podspec --allow-warnings 
load 'remove_unsupported_libraries.rb'
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '15.0'
use_frameworks!

target 'RemoteShutter' do
    pod 'SwiftLint', '~> 0.41.0'
    pod 'FlatBuffers', :podspec => 'LocalPodspecs/FlatBuffers.podspec.json'

    target 'RemoteShutterTests' do
        inherit! :search_paths
    end
end

target 'RemoteShutterWatch' do
    platform :watchos, '10.0'
    pod 'FlatBuffers', :podspec => 'LocalPodspecs/FlatBuffers.podspec.json'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      # No pod ships App Intents; skip the extractor so it doesn't warn.
      config.build_settings['LM_SKIP_METADATA_EXTRACTION'] = 'YES'
    end
  end
end
