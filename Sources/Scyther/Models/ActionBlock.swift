//
//  ActionBlock.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import Foundation

/// `typealias` representing `() -> Void` used to allow actions/events to be set on views.
public typealias ActionBlock = () -> Void
public typealias ActionBlockWithData<T> = (T?) -> Void
