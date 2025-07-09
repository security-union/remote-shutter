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
    pod 'Google-Mobile-Ads-SDK', '~> 11.0'
    pod 'GoogleUserMessagingPlatform', '~> 2.0'
    pod 'SwiftLint', '~> 0.41.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
      
      # Disable debug logging for Theater to prevent excessive frame message spam
      if target.name == 'Theater'
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'].delete('DEBUG=1')
        config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] ||= ['$(inherited)']
        config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].delete('DEBUG')
      end
    end
  end
end
