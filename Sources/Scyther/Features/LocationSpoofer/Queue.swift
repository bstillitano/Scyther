//
//  Queue.swift
//
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import CoreLocation

/// A node in a singly-linked list.
///
/// - Note: Internal implementation detail of `UniDirectionalLinkedList`.
fileprivate class Node<T> {
    /// The data stored in this node.
    let item: T

    /// Reference to the next node in the list, or `nil` if this is the tail.
    var next: Node<T>?

    /// Creates a new node with the specified item.
    ///
    /// - Parameter item: The data to store in this node.
    init(with item: T) {
        self.item = item
        self.next = nil
    }
}

/// A singly-linked list implementation used internally by `Queue`.
///
/// - Note: Internal implementation detail of `Queue`.
fileprivate class UniDirectionalLinkedList<T> {
    /// The first node in the list.
    fileprivate var head: Node<T>?

    /// The last node in the list.
    private var tail: Node<T>?

    /// Returns whether the list is empty.
    func isEmpty() -> Bool {
        return head == nil
    }

    /// Appends an item to the end of the list.
    ///
    /// - Parameter item: The item to append.
    func append(_ item: T) {
        let node = Node(with: item)
        if let lastNode = tail {
            lastNode.next = node
        } else {
            head = node
        }
        tail = node
    }
}

/// A FIFO (First In, First Out) queue data structure.
///
/// This queue is used by the location spoofer to store and process GPS coordinates
/// from GPX files in order. It's implemented using a singly-linked list for efficient
/// enqueue and dequeue operations.
///
/// ## Usage
/// ```swift
/// var queue = Queue<CLLocation>()
/// queue.enqueue(location1)
/// queue.enqueue(location2)
///
/// while !queue.isEmpty() {
///     if let location = queue.dequeue() {
///         // Process location
///     }
/// }
/// ```
struct Queue<T>: @unchecked Sendable {
    /// The underlying linked list storing the queue items.
    private let linkedList = UniDirectionalLinkedList<T>()

    /// Adds an item to the back of the queue.
    ///
    /// - Parameter item: The item to enqueue.
    func enqueue(_ item: T) {
        linkedList.append(item)
    }

    /// Removes and returns the item at the front of the queue.
    ///
    /// - Returns: The front item, or `nil` if the queue is empty.
    func dequeue() -> T? {
        guard let head = linkedList.head else {
            return nil
        }
        linkedList.head = head.next
        return head.item
    }

    /// Returns whether the queue is empty.
    ///
    /// - Returns: `true` if the queue contains no items, `false` otherwise.
    func isEmpty() -> Bool {
        return linkedList.isEmpty()
    }

    /// Returns the item at the front of the queue without removing it.
    ///
    /// - Returns: The front item, or `nil` if the queue is empty.
    func peek() -> T? {
        return linkedList.head?.item
    }
}
