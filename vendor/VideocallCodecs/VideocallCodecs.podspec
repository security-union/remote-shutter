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

  # The xcframework is self-describing: each slice carries its own
  # module.modulemap + videocall_codecsFFI.h, so `import videocall_codecsFFI`
  # in the generated Swift wrapper resolves from the vendored framework itself.
  # (Do NOT add a second, loose modulemap — it triggers "redefinition of module
  # 'videocall_codecsFFI'".)
  s.vendored_frameworks = 'VideocallCodecs.xcframework'
  s.source_files        = 'videocall_codecs.swift'

  # The simulator slices are arm64-only (the Rust build produces no x86_64
  # simulator objects), so tell Xcode not to try linking that arch there — a
  # multi-arch simulator build otherwise fails in ld. Applied to the consuming
  # app targets too (user_target_xcconfig): they link the framework and hit the
  # same missing-arch wall.
  #
  # macosx is NOT excluded: the Mac Catalyst and native macOS slices are fat
  # (arm64 + x86_64), so an Intel Mac Catalyst build links cleanly. Dropping the
  # x86_64 Catalyst arch is what triggered App Store rejection ITMS-90981.
  excluded = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'EXCLUDED_ARCHS[sdk=watchsimulator*]'  => 'x86_64'
  }
  s.pod_target_xcconfig  = { 'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES' }.merge(excluded)
  s.user_target_xcconfig = excluded
end
