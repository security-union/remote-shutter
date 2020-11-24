# Uncomment this line to define a global platform for your project
# platform :ios, '6.0'
# pod trunk push Theater.podspec --allow-warnings 
load 'remove_unsupported_libraries.rb'
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '12.0'
use_frameworks!

target 'RemoteShutter' do    
    pod 'Starscream', '~> 4.0.4'
    pod 'Theater', '~> 0.12'
    pod 'Google-Mobile-Ads-SDK', '~> 7.68.0'
    pod 'GoogleUserMessagingPlatform', '~> 1.3.0'
    pod 'SwiftLint', '~> 0.41.0'

end

def supported_pods
   ['Starscream', 'Theater']
end

def unsupported_pods
   ['Fabric', 'Crashlytics', 'Firebase/Core', "Google-Mobile-Ads-SDK", "GoogleUserMessagingPlatform"]
end

# install all pods except unsupported ones
post_install do |installer|
   installer.configure_support_catalyst(supported_pods, unsupported_pods)
end

