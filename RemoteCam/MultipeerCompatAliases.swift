//
//  MultipeerCompatAliases.swift
//  RemoteShutter
//
//  Thin-diff migration shim: the app keeps MultipeerConnectivity's type names
//  while the implementations come from PeerMesh's MPCCompat. This file is the
//  entire mapping — app code is otherwise unchanged from the MPC era, except
//  imports and the peer-ID cache (PeerID is Codable, not NSCoding).
//
//  PeerMesh deliberately does not publish MC-prefixed names; the aliases are
//  app-local. Behavioral deltas vs real MPC are documented on MultipeerSession
//  in MPCCompat (always-encrypted, no 8-peer cap, key-derived peer IDs).
//

import MPCCompat
import PeerMesh

public typealias MCPeerID = PeerID
public typealias MCSession = MultipeerSession
public typealias MCSessionDelegate = MultipeerSessionDelegate
public typealias MCSessionState = MultipeerSession.PeerState
public typealias MCSessionSendDataMode = MultipeerSession.SendDataMode
public typealias MCEncryptionPreference = MultipeerSession.EncryptionPreference
public typealias MCNearbyServiceAdvertiser = NearbyServiceAdvertiser
public typealias MCNearbyServiceAdvertiserDelegate = NearbyServiceAdvertiserDelegate
public typealias MCNearbyServiceBrowser = NearbyServiceBrowser
public typealias MCNearbyServiceBrowserDelegate = NearbyServiceBrowserDelegate
