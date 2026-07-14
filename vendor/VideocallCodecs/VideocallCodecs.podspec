Pod::Spec.new do |s|
  s.name             = 'VideocallCodecs'
  s.version          = '0.1.0'
  s.summary          = 'Pure-Rust VP9 codec (encoder + decoder) for Apple platforms.'
  s.description      = <<-DESC
    UniFFI Swift bindings for the pure-Rust VP9 encoder + keyframe/inter decoder
    from videocall-rs (videocall-codecs). Zero libvpx, zero C. Ships as a static
    xcframework with slices for iOS device/simulator, Mac Catalyst, macOS, and
    watchOS device/simulator, plus the generated Swift API.
  DESC
  s.homepage         = 'https://github.com/security-union/videocall-rs'
  s.license          = { :type => 'MIT OR Apache-2.0' }
  s.author           = { 'Security Union' => 'dario@securityunion.dev' }
  # Not fetched: this is a local pod referenced via `:path` in the Podfile.
  s.source           = { :git => 'https://github.com/security-union/videocall-rs.git', :tag => "videocall-codecs-#{s.version}" }

  s.ios.deployment_target     = '15.0'
  s.osx.deployment_target     = '12.0'
  s.watchos.deployment_target = '10.0'
  s.swift_version    = '5.0'

  # The static xcframework provides the linked symbols; the loose FFI/ dir
  # carries the C header + a modulemap so `import videocall_codecsFFI` resolves
  # (a static-lib xcframework's own module isn't exposed to Swift under
  # use_frameworks!). SWIFT_INCLUDE_PATHS puts that modulemap on the import path.
  s.vendored_frameworks = 'VideocallCodecs.xcframework'
  s.source_files        = 'videocall_codecs.swift'
  s.preserve_paths      = 'FFI/**'

  s.pod_target_xcconfig = {
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES',
    'SWIFT_INCLUDE_PATHS'            => '$(PODS_TARGET_SRCROOT)/FFI',
  }
end
