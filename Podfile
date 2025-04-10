# Uncomment this line to define a global platform for your project
# platform :ios, '6.0'
# pod trunk push Theater.podspec --allow-warnings 
load 'remove_unsupported_libraries.rb'
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '15.0'
use_frameworks!

target 'RemoteShutter' do    
    pod 'Starscream', '~> 4.0.8'
    pod 'Theater', '1.1'
    pod 'Google-Mobile-Ads-SDK', '~> 8.3.0'
    pod 'GoogleUserMessagingPlatform', '~> 1.3.0'
    pod 'SwiftLint', '~> 0.41.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
