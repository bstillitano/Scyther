//
//  Spacing.swift
//  Scyther
//
//  Created by Brandon Stillitano on 8/12/20.
//

import UIKit

/// `typealias` representing `UIEdgeInsets` used to enforce standard spacing sizes.
public typealias Spacing = UIEdgeInsets


/// Enum class used for creating constant margin insets based on a baseline grid of 8px.
private enum Margin: CGFloat {
    case x1 = 8
    case x2 = 16
    case x3 = 24
    case x4 = 32
    case x5 = 40
    case x6 = 48
    case x7 = 56
    case x8 = 64
    case x9 = 72
    case x10 = 80
}

extension Spacing {
    public static let globalMargin: Spacing = UIEdgeInsets(top: Margin.x2.rawValue,
                                                           left: Margin.x2.rawValue,
                                                           bottom: Margin.x2.rawValue,
                                                           right: Margin.x2.rawValue)

    public static let top2Left0Bottom2Right0: UIEdgeInsets = UIEdgeInsets(top: Margin.x2.rawValue,
                                                                          left: .zero,
                                                                          bottom: Margin.x2.rawValue,
                                                                          right: .zero)

    public static let top4Left2Bottom2Right2: UIEdgeInsets = UIEdgeInsets(top: Margin.x4.rawValue,
                                                                          left: Margin.x2.rawValue,
                                                                          bottom: Margin.x2.rawValue,
                                                                          right: Margin.x2.rawValue)

    public static let top0Left2Bottom2Right2: UIEdgeInsets = UIEdgeInsets(top: .zero,
                                                                          left: Margin.x2.rawValue,
                                                                          bottom: Margin.x2.rawValue,
                                                                          right: Margin.x2.rawValue)
}
