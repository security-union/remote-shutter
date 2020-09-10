# Uncomment this line to define a global platform for your project
# platform :ios, '6.0'
# pod trunk push Theater.podspec --allow-warnings 

source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '8.0'
use_frameworks!

def gallery
    pod 'BFGallery' , :git => "https://github.com/darioalessandro/BlackFireGallery.git", :tag => "0.1.5"
end

target 'RemoteShutter' do
    gallery    
    pod 'Starscream', '~> 3.0.6'
    pod 'Theater', '~> 0.9.1'
end

