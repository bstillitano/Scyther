// swiftlint:disable all
//
//  LinkedList.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

import Foundation

public struct LinkedList<ELEMENT> {

    private var headNode: Node?
    private var tailNode: Node?
    public private(set) var count: Int = 0
    private var id = ID()
    public init() {
        //Intentionally unimplemented
    }

    fileprivate class ID {
        init() {
            //Intentionally unimplemented
        }
    }
}

//MARK: - LinkedList Node
extension LinkedList {

    fileprivate class Node {
        public var value: Element
        public var next: Node?
        public weak var previous: Node?

        public init(value: Element) {
            self.value = value
        }
    }

}

//MARK: - Initializers
public extension LinkedList {

    private init(_ nodeChain: (head: Node, tail: Node, count: Int)?) {
        guard let chain = nodeChain else {
            return
        }
        headNode = chain.head
        tailNode = chain.tail
        count = chain.count
    }

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
    // Creates a chain of nodes from a sequence. Returns `nil` if the sequence is empty.
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
    var head: Element? {
        return headNode?.value
    }

    var tail: Element? {
        return tailNode?.value
    }
}

//MARK: - Sequence Conformance
extension LinkedList: Sequence {

    public typealias ELEMENT = Element

    public __consuming func makeIterator() -> Iterator {
        return Iterator(node: headNode)
    }

    public struct Iterator: IteratorProtocol {

        private var currentNode: Node?

        fileprivate init(node: Node?) {
            currentNode = node
        }

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

    public var startIndex: Index {
        return Index(node: headNode, offset: 0, id: id)
    }

    public var endIndex: Index {
        return Index(node: nil, offset: count, id: id)
    }

    public var first: Element? {
        return head
    }

    public var isEmpty: Bool {
        return count == 0
    }

    public func index(after i: Index) -> Index {
        precondition(i.listID === self.id, "LinkedList index is invalid")
        precondition(i.offset != endIndex.offset, "LinkedList index is out of bounds")
        return Index(node: i.node?.next, offset: i.offset + 1, id: id)
    }

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

    mutating func prepend(_ newElement: Element) {
        replaceSubrange(startIndex..<startIndex, with: CollectionOfOne(newElement))
    }

    mutating func prepend<S>(contentsOf newElements: __owned S) where S: Sequence, S.Element == Element {
        replaceSubrange(startIndex..<startIndex, with: newElements)
    }

    @discardableResult
    mutating func popFirst() -> Element? {
        if isEmpty {
            return nil
        }
        return removeFirst()
    }

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
    public var last: Element? {
        return tail
    }

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
    public mutating func append<S>(contentsOf newElements: __owned S) where S: Sequence, Element == S.Element {
        replaceSubrange(endIndex..<endIndex, with: newElements)
    }

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
