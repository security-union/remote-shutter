//
//  RemoteCamSystem.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation

/// The app-wide Theater actor system. All RemoteCam actors
/// ("RemoteCam Session", "FrameSender", "MonitorActor", ...) are registered
/// under this system and looked up via `selectActor(actorPath:)`.
public class RemoteCamSystem: ActorSystem {
    static let shared = ActorSystem(name: "RemoteCam")
}
