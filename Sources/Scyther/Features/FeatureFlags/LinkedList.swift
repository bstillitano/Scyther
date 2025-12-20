// swiftlint:disable all
//
//  LinkedList.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

import Foundation

/// A generic doubly-linked list implementation with value semantics and copy-on-write behavior.
///
/// `LinkedList` provides an efficient data structure for sequential element storage with constant-time
/// insertion and removal at both ends. It conforms to `Collection`, `BidirectionalCollection`,
/// `MutableCollection`, and `RangeReplaceableCollection`, providing full Swift collection semantics.
///
/// ## Features
/// - **Doubly-linked nodes**: Each node maintains references to both previous and next nodes
/// - **Copy-on-write semantics**: Modifications trigger copies only when the list is shared
/// - **Value type**: Despite using class-based nodes internally, the list behaves as a value type
/// - **O(1) operations**: Constant-time insertion/removal at head and tail
///
/// ## Usage
/// ```swift
/// var list = LinkedList<Int>()
/// list.append(1)
/// list.append(2)
/// list.prepend(0)
/// // list is now [0, 1, 2]
///
/// list.popFirst() // returns 0
/// list.popLast()  // returns 2
/// // list is now [1]
/// ```
public struct LinkedList<ELEMENT> {

    private var headNode: Node?
    private var tailNode: Node?

    /// The number of elements in the linked list.
    ///
    /// Accessing this property is O(1).
    public private(set) var count: Int = 0
    private var id = ID()

    /// Creates an empty linked list.
    public init() {
        //Intentionally unimplemented
    }

    /// Internal identifier used to validate that indices belong to this list instance.
    fileprivate class ID {
        init() {
            //Intentionally unimplemented
        }
    }
}

//MARK: - LinkedList Node
extension LinkedList {

    /// A node in the doubly-linked list that stores an element and references to adjacent nodes.
    fileprivate class Node {
        /// The element stored in this node.
        public var value: Element

        /// Reference to the next node in the list, or `nil` if this is the tail.
        public var next: Node?

        /// Weak reference to the previous node in the list, or `nil` if this is the head.
        public weak var previous: Node?

        /// Creates a new node with the given value.
        /// - Parameter value: The element to store in this node.
        public init(value: Element) {
            self.value = value
        }
    }

}

//MARK: - Initializers
public extension LinkedList {

    /// Creates a linked list from a node chain tuple.
    /// - Parameter nodeChain: An optional tuple containing head node, tail node, and count.
    private init(_ nodeChain: (head: Node, tail: Node, count: Int)?) {
        guard let chain = nodeChain else {
            return
        }
        headNode = chain.head
        tailNode = chain.tail
        count = chain.count
    }

    /// Creates a linked list from any sequence.
    ///
    /// If the sequence is already a `LinkedList`, it is copied directly. Otherwise,
    /// the sequence elements are chained into a new linked list.
    ///
    /// - Parameter sequence: The sequence of elements to create the list from.
    /// - Complexity: O(*n*) where *n* is the number of elements in the sequence.
    init<S>(_ sequence: S) where S: Sequence, S.Element == Element {
        if let linkedList = sequence as? LinkedList<Element> {
            self = linkedList
        } else {
            self = LinkedList(chain(of: sequence))
        }
    }

}

//MARK: Chain of Nodes
extension LinkedList {
    /// Creates a chain of nodes from a sequence.
    ///
    /// - Parameter sequence: The sequence to create nodes from.
    /// - Returns: A tuple containing the head node, tail node, and count, or `nil` if the sequence is empty.
    /// - Complexity: O(*n*) where *n* is the number of elements in the sequence.
    private func chain<S>(of sequence: S) -> (head: Node, tail: Node, count: Int)? where S: Sequence, S.Element == Element {
        var iterator = sequence.makeIterator()
        var head: Node
        var tail: Node
        var count = 0
        guard let firstValue = iterator.next() else {
            return nil
        }

        var currentNode = Node(value: firstValue)
        head = currentNode
        count = 1

        while let nextElement = iterator.next() {
            let nextNode = Node(value: nextElement)
            currentNode.next = nextNode
            nextNode.previous = currentNode
            currentNode = nextNode
            count += 1
        }
        tail = currentNode
        return (head: head, tail: tail, count: count)
    }
}

//MARK: - Copy Nodes
extension LinkedList {

    /// Creates a copy of all nodes, setting a specific node to a new value.
    ///
    /// This method is used for copy-on-write semantics when modifying a shared list.
    ///
    /// - Parameters:
    ///   - index: The index of the node to update with the new value.
    ///   - value: The new value to set at the specified index.
    /// - Complexity: O(*n*) where *n* is the number of elements in the list.
    mutating func copyNodes(settingNodeAt index: Index, to value: Element) {

        var currentIndex = startIndex
        var currentNode = Node(value: currentIndex == index ? value : currentIndex.node!.value)
        let newHeadNode = currentNode
        currentIndex = self.index(after: currentIndex)

        while currentIndex < endIndex {
            let nextNode = Node(value: currentIndex == index ? value : currentIndex.node!.value)
            currentNode.next = nextNode
            nextNode.previous = currentNode
            currentNode = nextNode
            currentIndex = self.index(after: currentIndex)
        }
        headNode = newHeadNode
        tailNode = currentNode
    }

    /// Creates a copy of all nodes, excluding nodes in the specified range.
    ///
    /// This method is used for copy-on-write semantics when removing elements from a shared list.
    ///
    /// - Parameter range: The range of indices to exclude from the copy.
    /// - Returns: The range where the removed elements would have been in the new list.
    /// - Complexity: O(*n*) where *n* is the number of elements in the list.
    @discardableResult
    mutating func copyNodes(removing range: Range<Index>) -> Range<Index> {

        id = ID()
        var currentIndex = startIndex

        while range.contains(currentIndex) {
            currentIndex = index(after: currentIndex)
        }

        guard let headValue = currentIndex.node?.value else {
            self = LinkedList()
            return endIndex..<endIndex
        }

        var currentNode = Node(value: headValue)
        let newHeadNode = currentNode
        var newCount = 1

        var removedRange: Range<Index> = Index(node: currentNode, offset: 0, id: id)..<Index(node: currentNode, offset: 0, id: id)
        currentIndex = index(after: currentIndex)

        while currentIndex < endIndex {
            guard !range.contains(currentIndex) else {
                currentIndex = index(after: currentIndex)
                continue
            }

            let nextNode = Node(value: currentIndex.node!.value)
            if currentIndex == range.upperBound {
                removedRange = Index(node: nextNode, offset: newCount, id: id)..<Index(node: nextNode, offset: newCount, id: id)
            }
            currentNode.next = nextNode
            nextNode.previous = currentNode
            currentNode = nextNode
            newCount += 1
            currentIndex = index(after: currentIndex)

        }
        if currentIndex == range.upperBound {
            removedRange = Index(node: nil, offset: newCount, id: id)..<Index(node: nil, offset: newCount, id: id)
        }
        headNode = newHeadNode
        tailNode = currentNode
        count = newCount
        return removedRange
    }

}


//MARK: - Computed Properties
public extension LinkedList {
    /// The first element in the list, or `nil` if the list is empty.
    ///
    /// - Complexity: O(1)
    var head: Element? {
        return headNode?.value
    }

    /// The last element in the list, or `nil` if the list is empty.
    ///
    /// - Complexity: O(1)
    var tail: Element? {
        return tailNode?.value
    }
}

//MARK: - Sequence Conformance
extension LinkedList: Sequence {

    public typealias ELEMENT = Element

    /// Creates an iterator over the elements of the list.
    ///
    /// - Returns: An iterator that traverses the list from head to tail.
    /// - Complexity: O(1)
    public __consuming func makeIterator() -> Iterator {
        return Iterator(node: headNode)
    }

    /// An iterator over the elements of a linked list.
    public struct Iterator: IteratorProtocol {

        private var currentNode: Node?

        /// Creates an iterator starting at the given node.
        /// - Parameter node: The starting node, or `nil` for an empty iterator.
        fileprivate init(node: Node?) {
            currentNode = node
        }

        /// Advances to the next element and returns it, or `nil` if no next element exists.
        ///
        /// - Returns: The next element in the sequence, or `nil`.
        /// - Complexity: O(1)
        public mutating func next() -> Element? {
            guard let node = currentNode else {
                return nil
            }
            currentNode = node.next
            return node.value
        }

    }
}

//MARK: - Collection Conformance
extension LinkedList: Collection {

    /// The position of the first element in the list.
    ///
    /// - Complexity: O(1)
    public var startIndex: Index {
        return Index(node: headNode, offset: 0, id: id)
    }

    /// The list's "past the end" position—that is, the position one greater than the last valid subscript argument.
    ///
    /// - Complexity: O(1)
    public var endIndex: Index {
        return Index(node: nil, offset: count, id: id)
    }

    /// The first element in the list, or `nil` if the list is empty.
    ///
    /// - Complexity: O(1)
    public var first: Element? {
        return head
    }

    /// A Boolean value indicating whether the list is empty.
    ///
    /// - Complexity: O(1)
    public var isEmpty: Bool {
        return count == 0
    }

    /// Returns the position immediately after the given index.
    ///
    /// - Parameter i: A valid index of the list.
    /// - Returns: The index value immediately after `i`.
    /// - Complexity: O(1)
    public func index(after i: Index) -> Index {
        precondition(i.listID === self.id, "LinkedList index is invalid")
        precondition(i.offset != endIndex.offset, "LinkedList index is out of bounds")
        return Index(node: i.node?.next, offset: i.offset + 1, id: id)
    }

    /// A position in a linked list.
    ///
    /// Indices maintain weak references to their associated nodes and list ID to ensure validity.
    public struct Index: Comparable {
        fileprivate weak var node: Node?
        fileprivate var offset: Int
        fileprivate weak var listID: ID?

        fileprivate init(node: Node?, offset: Int, id: ID) {
            self.node = node
            self.offset = offset
            self.listID = id
        }

        public static func == (lhs: Index, rhs: Index) -> Bool {
            return lhs.offset == rhs.offset
        }

        public static func < (lhs: Index, rhs: Index) -> Bool {
            return lhs.offset < rhs.offset
        }
    }

}


//MARK: - MutableCollection Conformance
extension LinkedList: MutableCollection {

    /// Accesses the element at the specified position.
    ///
    /// - Parameter position: The position of the element to access.
    /// - Returns: The element at the specified position.
    /// - Complexity: O(1) for get, O(*n*) for set when copy-on-write triggers, O(1) otherwise.
    public subscript(position: Index) -> ELEMENT {
        get {
            precondition(position.listID === self.id, "LinkedList index is invalid")
            precondition(position.offset != endIndex.offset, "Index out of range")
            guard let node = position.node else {
                preconditionFailure("LinkedList index is invalid")
            }
            return node.value
        }
        set {
            precondition(position.listID === self.id, "LinkedList index is invalid")
            precondition(position.offset != endIndex.offset, "Index out of range")

            // Copy-on-write semantics for nodes
            if !isKnownUniquelyReferenced(&headNode) {
                copyNodes(settingNodeAt: position, to: newValue)
            } else {
                position.node?.value = newValue
            }
        }
    }
}

//MARK: LinkedList Specific Operations
public extension LinkedList {

    /// Adds a new element at the beginning of the list.
    ///
    /// - Parameter newElement: The element to insert at the start.
    /// - Complexity: O(1)
    mutating func prepend(_ newElement: Element) {
        replaceSubrange(startIndex..<startIndex, with: CollectionOfOne(newElement))
    }

    /// Adds the elements of a sequence to the beginning of the list.
    ///
    /// - Parameter newElements: The elements to insert at the start.
    /// - Complexity: O(*m*) where *m* is the length of `newElements`.
    mutating func prepend<S>(contentsOf newElements: __owned S) where S: Sequence, S.Element == Element {
        replaceSubrange(startIndex..<startIndex, with: newElements)
    }

    /// Removes and returns the first element of the list.
    ///
    /// - Returns: The first element, or `nil` if the list is empty.
    /// - Complexity: O(1)
    @discardableResult
    mutating func popFirst() -> Element? {
        if isEmpty {
            return nil
        }
        return removeFirst()
    }

    /// Removes and returns the last element of the list.
    ///
    /// - Returns: The last element, or `nil` if the list is empty.
    /// - Complexity: O(1)
    @discardableResult
    mutating func popLast() -> Element? {
        if isEmpty {
            return nil
        }
        return removeLast()
    }
}

//MARK: - BidirectionalCollection Conformance
extension LinkedList: BidirectionalCollection {
    /// The last element in the list, or `nil` if the list is empty.
    ///
    /// - Complexity: O(1)
    public var last: Element? {
        return tail
    }

    /// Returns the position immediately before the given index.
    ///
    /// - Parameter i: A valid index of the list.
    /// - Returns: The index value immediately before `i`.
    /// - Complexity: O(1)
    public func index(before i: Index) -> Index {
        precondition(i.listID === self.id, "LinkedList index is invalid")
        precondition(i.offset != startIndex.offset, "LinkedList index is out of bounds")
        if i.offset == count {
            return Index(node: tailNode, offset: i.offset - 1, id: id)
        }
        return Index(node: i.node?.previous, offset: i.offset - 1, id: id)
    }

}

//MARK: - RangeReplaceableCollection Conformance
extension LinkedList: RangeReplaceableCollection {
    /// Adds the elements of a sequence to the end of the list.
    ///
    /// - Parameter newElements: The elements to append.
    /// - Complexity: O(*m*) where *m* is the length of `newElements`.
    public mutating func append<S>(contentsOf newElements: __owned S) where S: Sequence, Element == S.Element {
        replaceSubrange(endIndex..<endIndex, with: newElements)
    }

    /// Replaces the elements in the specified subrange with the given elements.
    ///
    /// - Parameters:
    ///   - subrange: The range of elements to replace.
    ///   - newElements: The new elements to insert.
    /// - Complexity: O(*n* + *m*) where *n* is the length of the list and *m* is the length of `newElements`.
    public mutating func replaceSubrange<S, R>(_ subrange: R, with newElements: __owned S) where S: Sequence, R: RangeExpression, Element == S.Element, Index == R.Bound {

        var range = subrange.relative(to: indices)
        precondition(range.lowerBound.listID === id && range.upperBound.listID === id, "LinkedList range of indices are invalid")
        precondition(range.lowerBound >= startIndex && range.upperBound <= endIndex, "Subrange bounds are out of range")

        // If range covers all elements and the new elements are a LinkedList then set references to it
        if range.lowerBound == startIndex, range.upperBound == endIndex, let linkedList = newElements as? LinkedList {
            self = linkedList
            return
        }

        // There are no new elements, so range indicates deletion
        guard let nodeChain = chain(of: newElements) else {

            // If there is nothing in the removal range
            // This also covers the case that the linked list is empty because this is the only possible range
            guard range.lowerBound != range.upperBound else {
                return
            }

            // Deletion range spans all elements
            if range.lowerBound == startIndex && range.upperBound == endIndex {
                headNode = nil
                tailNode = nil
                count = 0
                return
            }

            // Copy-on-write semantics for nodes and remove elements in range
            guard isKnownUniquelyReferenced(&headNode) else {
                copyNodes(removing: range)
                return
            }

            // Update count after mutation to preserve startIndex and endIndex validity
            defer {
                count = count - (range.upperBound.offset - range.lowerBound.offset)
            }

            // Move head up if deletion starts at start index
            if range.lowerBound == startIndex {
                // Can force unwrap node since the upperBound is not the end index
                headNode = range.upperBound.node!
                headNode!.previous = nil

                // Move tail back if deletion ends at end index
            } else if range.upperBound == endIndex {
                // Can force unwrap since lowerBound index must have an associated element
                tailNode = range.lowerBound.node!.previous
                tailNode!.next = nil

                // Deletion range is in the middle of the linked list
            } else {
                // Can force unwrap all bound nodes since they both must have elements
                range.upperBound.node!.previous = range.lowerBound.node!.previous
                range.lowerBound.node!.previous!.next = range.upperBound.node!
            }

            return
        }

        // Replace entire content of list with new elements
        if range.lowerBound == startIndex && range.upperBound == endIndex {
            headNode = nodeChain.head
            tailNode = nodeChain.tail
            count = nodeChain.count
            return
        }

        // Copy-on-write semantics for nodes before mutation
        if !isKnownUniquelyReferenced(&headNode) {
            range = copyNodes(removing: range)
        }

        // Update count after mutation to preserve startIndex and endIndex validity
        defer {
            count += nodeChain.count - (range.upperBound.offset - range.lowerBound.offset)
        }

        // Prepending new elements
        guard range.upperBound != startIndex else {
            headNode?.previous = nodeChain.tail
            nodeChain.tail.next = headNode
            headNode = nodeChain.head
            return
        }

        // Appending new elements
        guard range.lowerBound != endIndex else {
            tailNode?.next = nodeChain.head
            nodeChain.head.previous = tailNode
            tailNode = nodeChain.tail
            return
        }

        if range.lowerBound == startIndex {
            headNode = nodeChain.head
        }
        if range.upperBound == endIndex {
            tailNode = nodeChain.tail
        }

        range.lowerBound.node!.previous!.next = nodeChain.head
        range.upperBound.node!.previous = nodeChain.tail
    }
}

//MARK: - ExpressibleByArrayLiteral Conformance
extension LinkedList: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = Element

    public init(arrayLiteral elements: ArrayLiteralElement...) {
        self.init(elements)
    }
}

//MARK: - CustomStringConvertible Conformance
extension LinkedList: CustomStringConvertible {
    public var description: String {
        return "[" + lazy.map { "\($0)" }.joined(separator: ", ") + "]"
    }
}

//MARK: - Equatable Conformance
extension LinkedList: Equatable where ELEMENT: Equatable {
    public static func == (lhs: LinkedList<Element>, rhs: LinkedList<Element>) -> Bool {
        for (a, b) in zip(lhs, rhs) {
            guard a == b else {
                return false
            }
        }
        return true
    }
}
