//
//  DemoModels.swift
//  ScytherExample
//
//  Created by Brandon Stillitano on 4/1/2026.
//

import Foundation
import SwiftData

/// A demo user model for testing the Database Browser feature.
@Model
final class DemoUser {
    var name: String
    var email: String
    var age: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \DemoPost.user) var posts: [DemoPost]

    init(name: String, email: String, age: Int) {
        self.name = name
        self.email = email
        self.age = age
        self.createdAt = Date()
        self.posts = []
    }
}

/// A demo post model for testing relationships in the Database Browser.
@Model
final class DemoPost {
    var title: String
    var content: String
    var publishedAt: Date
    var user: DemoUser?

    init(title: String, content: String, user: DemoUser? = nil) {
        self.title = title
        self.content = content
        self.publishedAt = Date()
        self.user = user
    }
}

/// A demo product model for testing various data types.
@Model
final class DemoProduct {
    var name: String
    var price: Double
    var inStock: Bool
    var category: String

    init(name: String, price: Double, inStock: Bool, category: String) {
        self.name = name
        self.price = price
        self.inStock = inStock
        self.category = category
    }
}
