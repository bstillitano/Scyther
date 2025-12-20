//
//  File.swift
//  
//
//  Created by Brandon Stillitano on 27/9/21.
//

import Foundation
import CoreLocation

fileprivate class Node<T> {
    let item: T
    var next: Node<T>?
    
    init(with item: T) {
        self.item = item
        self.next = nil
    }
}

fileprivate class UniDirectionalLinkedList<T> {
    fileprivate var head: Node<T>?
    private var tail: Node<T>?
    
    func isEmpty() -> Bool {
        return head == nil
    }
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

struct Queue<T> {
    private let linkedList = UniDirectionalLinkedList<T>()
    
    func enqueue(_ item: T) {
        linkedList.append(item)
    }
    func dequeue() -> T? {
        guard let head = linkedList.head else {
            return nil
        }
        linkedList.head = head.next
        return head.item
    }
    
    func isEmpty() -> Bool {
        return linkedList.isEmpty()
    }
    
    func peek() -> T? {
        return linkedList.head?.item
    }
}
