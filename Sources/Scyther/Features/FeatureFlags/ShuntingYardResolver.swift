//
//  ShuntingYardResolver.swift
//  Scyther
//
//  Created by Brandon Stillitano on 4/12/20.
//

#if !os(macOS)
import UIKit

/**
 Enum class used for strongly tpying A/B conditions. Conditions must be listed here to be used as conditions on the server.
 */
public enum Condition: String, CaseIterable {
    /**
     The current version of the running application. E.g. `52.0` (this is not the build number).
     */
    case appVersion

    /**
     The current build number of the running application. E.g. `4356092` (this is not the app version).
     */
    case buildNumber

    /**
     The generation of the running device. E.g. `10` (Where there have been 10 devices released, this would represent the newest device).
     */
    case deviceGeneration

    /**
     The current model of the running device. E.g. `iPhone12.5` (iPhone 11 Pro Max).
     These can be found here https://gist.github.com/adamawolf/3048717.
     */
    case deviceModel

    /**
     The name assigned, by the device user, to the running device. E.g. `Brandon's iPhone 11 Pro Max`.
     */
    case deviceName

    /**
     The type of device currently being used. E.g. `simulator`, `phone`, `tablet`, etc.
     */
    case deviceType

    /**
     Will always return `iOS`.
     */
    case operatingSystem

    /**
     The cohort of users the running device falls into. This is based on `ShuntingYardResolver.instance.cohortPercentage`.
     */
    case percentage

    /**
     Current operating system version on the running device. E.g. `13.3`.
     */
    case systemVersion
}

/**
 Enum class used for strongly typing Operators such as !=, ==, etc.
 */
public enum Operator: String, CaseIterable {
    case notEqualTo = "~"
    case lessThan = "<"
    case lessThanOrEqualTo = "$"
    case equalTo = "="
    case greaterThan = ">"
    case greaterThanOrEqualTo = "#"
    case and = "&"
    case or = "|"

    /**
     Collection of values representing operators that are able to make a relational comparison between two values.
     */
    static var relationalOperators: [Operator] {
        return [.notEqualTo, .lessThan, .lessThanOrEqualTo, .equalTo, .greaterThan, .greaterThanOrEqualTo]
    }
}

/**
 Data class used for providing meaningful messages pertaining an attempt to validate a specific set of conditions.
 */
public struct Validation {
    public init() {
        // Intentionally unimplemented...
    }

    var result: Bool = false
    var message: String = ""
}

/**
 A strongly typed and performant class capable of resolving complex string logic and returning a comparison as a single Bool value.
 */
public class ShuntingYardResolver {
    /**
     Singleton instance of this class to allow performant usage of the utility.
     */
    static let instance: ShuntingYardResolver = ShuntingYardResolver()

    /**
     Private init to stop re-initialisation
     */
    private init() { }

    /**
     Value representing an opening bracket `(`.
     */
    let leftToken: String = "("

    /**
    Value representing a closing bracket `)`.
    */
    let rightToken: String = ")"

    /**
    Parses a string in the format "(a == b || c == d) && (x == y) || (foo == bar && day >= night)" where `||` represents `OR` conditions and `&&` represents an `AND` condition.
    
    - Parameter expression: The entire string that represents ALL the conditions to be resolved.
    
    - Returns: A boolean value representing whether ALL conditions have been met or not.
    
    - Complexity: O(*n*) where *n* is the the number of conditions in the group
    */
    public func evaluate(expression: String?) -> Bool {
        let tokens = expression?.splitByTokens ?? []
        let postfix = applyShuntingYard(tokens: tokens)
        return evaluatePostfix(postfix: postfix)
    }

    /**
    Parses a string in the format "(a == b || c == d) && (x == y) || (foo == bar && day >= night)" where `||` represents `OR` conditions and `&&` represents an `AND` condition.
    
    - Parameter postfix: The confitions to be evaluated broken down into a `LinkedList`
    
    - Returns: A boolean value representing whether ALL conditions have been met or not.
    
    - Complexity: O(*n*) where *n* is the the number of conditions in the list.
    */
    private func evaluatePostfix(postfix: LinkedList<String>) -> Bool {
        var outputStack = Stack<String>()
        postfix.reversed().forEach { string in
            if string.isOperand {
                outputStack.push(string)
            } else {
                let rhs = outputStack.pop()
                let lhs = outputStack.pop()
                if rhs?.bool != nil && lhs?.bool != nil {
                    outputStack.push(compareConditionWithOperator(lhs: lhs ?? "", rhs: rhs ?? "", operation: string) ? "true" : "false")
                } else if let operatorValue: Operator = Operator(rawValue: string),
                    let condition: Condition = Condition(rawValue: lhs ?? "") {
                    outputStack.push(
                        self.compareCondition(lhs: condition, rhs: rhs ?? "", operation: operatorValue) ? "true" : "false"
                    )
                } else {
                    outputStack.push("false")
                }
            }
        }
        return outputStack.top?.bool ?? false
    }

    /**
    Applies the ShuntingYard algorithm to an array of tokenized strings and returns them in a `LinkedList<String>` object.
     
    - Parameters:
        - tokens: The values that will be used as the candidates for algorithmic transformation.
    
    - Returns: A list of values that have been transformed via the Shunting Yard algorithm.
    
    - Complexity: O(*n*) where *n* is the number of items in the array of tokens.
    */
    private func applyShuntingYard(tokens: [String]) -> LinkedList<String> {
        //Itterate Data
        var outputQueue = LinkedList<String>()
        var operatorStack = Stack<String>()
        tokens.forEach { token in
            if token.isOperand {
                outputQueue.append(token)
            } else if token.isOperator {
                while isOperatorPrecedenceHigherOrEqual(token: token, operatorStack: operatorStack) {
                    outputQueue.append(operatorStack.pop() ?? "")
                }
                operatorStack.push(token)
            } else if token == self.leftToken {
                operatorStack.push(token)
            } else if token == self.rightToken {
                while operatorStack.top != nil && operatorStack.top != self.leftToken {
                    outputQueue.append(operatorStack.pop() ?? "")
                    if operatorStack.top == self.leftToken {
                        _ = operatorStack.pop()
                    }
                }
            }
        }

        //Clean Data
        while operatorStack.isNotEmpty {
            outputQueue.append(operatorStack.pop() ?? "")
        }
        outputQueue.reverse()
        return outputQueue
    }

    /**
    Determines whether the operator is of higher or equal precendence than the token.
     
    - Parameters:
        - token: The value that will be used as the left-hand side of the comparison.
        - operatorStack: The value that will be used as the right-hand side of the comparison.
    
    - Returns: A boolean value indicating whether the operator is of higher or equal precendence than the token.
    
    - Complexity: O(*1*)
    */
    private func isOperatorPrecedenceHigherOrEqual(token: String, operatorStack: Stack<String>) -> Bool {
        guard let top: String = operatorStack.top else {
            return false
        }
        return top.isOperator && top != self.leftToken && doesTopHaveHigherOrEqualPrecedence(input: token, top: top)
    }

    /**
    Determines whether the top is of higher or equal precendence than the input.
     
    - Parameters:
        - token: The value that will be used as the left-hand side of the comparison.
        - input: The value that will be used as the right-hand side of the comparison.
    
    - Returns: A boolean value indicating whether the top is of higher or equal precendence than the input.
    
    - Complexity: O(*1*)
    */
    private func doesTopHaveHigherOrEqualPrecedence(input: String, top: String) -> Bool {
        guard let topOperator: Operator = Operator(rawValue: top) else {
            return false
        }
        guard let inputOperator: Operator = Operator(rawValue: input) else {
            return false
        }
        let isTopRelationalOp = Operator.relationalOperators.contains(topOperator)
        let isInputRelationalOp = Operator.relationalOperators.contains(inputOperator)
        return isTopRelationalOp ? isTopRelationalOp : !(isTopRelationalOp || isInputRelationalOp)
    }

    /**
    Extracts all the operand type characters from a `Stack<Character>` type object into a single `String`
     
    - Parameters:
        - stack: The value that will be used as the left-hand side of the comparison.
    
    - Returns: A string value representing an array of operand characters without spaces.
    
    - Complexity: O(*n*) where *n* is the number of items on the stack.
    */
    func getOperand(stack: Stack<Character>) -> String {
        var value: String = ""
        stack.array.forEach { character in
            value.append(character)
        }
        return value
    }

    /**
     Value calculated by generating a UUID and hasing it followed by a mutation into a percentage value.
     This value is stored in UserDefaults and will persist between sessions.
     */
    public func cohortPercentage(override key: String = "Scyther_abTestingPercentageValue") -> Float {
        //Check if Value is Set in UserDefaults
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.float(forKey: key)
        }

        //Calculate Percentage
        let percentValue: Float = Float.random(in: 0...100)

        //Set Default
        UserDefaults.standard.set(percentValue, forKey: key)

        return percentValue
    }

    /**
    Compares a condition with a value and returns a Bool value indicating its equality.
    
    - Parameters:
        - lhs: The condition that will be used as the left-hand side of the comparison.
        - rhs: The value that will be used as the right-hand side of the comparison.
        - operation: The type of operation that will be used to perform the comparison.
    
    - Returns: A boolean value indicating whether the lhs is equal to the rhs based on the operator.
    
    - Complexity: O(*1*)
    */
    private func compareCondition(lhs: Condition, rhs: String, operation: Operator) -> Bool {
        //Perform Comparison
        switch lhs {
        case .appVersion:
            guard let rhs: Float = Float(rhs) else {
                return false
            }
            guard let lhs: Float = Float(UIApplication.shared.appVersion ?? "") else {
                return false
            }
            return self.compare(lhs: lhs, rhs: rhs, operation: operation)

        case .buildNumber:
            guard let rhs: Int = Int(rhs) else {
                return false
            }
            guard let lhs: Int = Int(UIApplication.shared.buildNumber ?? "") else {
                return false
            }
            return self.compare(lhs: lhs, rhs: rhs, operation: operation)

        case .deviceModel:
            return self.compare(lhs: UIDevice.current.modelName, rhs: rhs, operation: operation)

        case .deviceName:
            return self.compare(lhs: UIDevice.current.name, rhs: rhs, operation: operation)

        case .deviceType:
            return self.compare(lhs: UIDevice.current.deviceType, rhs: rhs, operation: operation)

        case .deviceGeneration:
            guard let rhs: Float = Float(rhs) else {
                return false
            }
            return self.compare(lhs: UIDevice.current.generation, rhs: rhs, operation: operation)

        case .operatingSystem:
            return self.compare(lhs: "iOS", rhs: rhs, operation: operation)

        case .percentage:
            return compareConditionForPercentage(rhs: rhs, operation: operation)

        case .systemVersion:
            return self.compare(lhs: UIDevice.current.systemVersion, rhs: rhs, operation: operation)
        }
    }

    private func compareConditionForPercentage(rhs: String, operation: Operator) -> Bool {
        guard let percentage: Float = Float(rhs) else {
            return false
        }
        return self.compare(lhs: self.cohortPercentage(), rhs: percentage, operation: operation)
    }

    /**
    Compares a single Float value to another Float value using the operation as a comparison type.
     
    - Parameters:
        - lhs: The value that will be used as the left-hand side of the comparison.
        - rhs: The value that will be used as the right-hand side of the comparison.
        - operation: The type of operation that will be used to perform the comparison.
    
    - Returns: A boolean value indicating whether the lhs is equal to the rhs based on the operator.
    
    - Complexity: O(*1*)
    */
    private func compare(lhs: Float, rhs: Float, operation: Operator) -> Bool {
        //Compare Data
        switch operation {
        case .equalTo:
            return lhs == rhs

        case .greaterThan:
            return lhs > rhs

        case .greaterThanOrEqualTo:
            return lhs >= rhs

        case .notEqualTo:
            return lhs != rhs

        case .lessThan:
            return lhs < rhs

        case .lessThanOrEqualTo:
            return lhs <= rhs

        default:
            return false
        }
    }

    /**
    Compares a single Int value to another Int value using the operation as a comparison type.
     
    - Parameters:
        - lhs: The value that will be used as the left-hand side of the comparison.
        - rhs: The value that will be used as the right-hand side of the comparison.
        - operation: The type of operation that will be used to perform the comparison.
    
    - Returns: A boolean value indicating whether the lhs is equal to the rhs based on the operator.
    
    - Complexity: O(*1*)
    */
    private func compare(lhs: Int, rhs: Int, operation: Operator) -> Bool {
        //Compare Data
        switch operation {
        case .equalTo:
            return lhs == rhs

        case .greaterThan:
            return lhs > rhs

        case .greaterThanOrEqualTo:
            return lhs >= rhs

        case .notEqualTo:
            return lhs != rhs

        case .lessThan:
            return lhs < rhs

        case .lessThanOrEqualTo:
            return lhs <= rhs

        default:
            return false
        }
    }

    /**
    Compares a single String value to another String value using the operation as a comparison type.
     
    - Parameters:
        - lhs: The value that will be used as the left-hand side of the comparison.
        - rhs: The value that will be used as the right-hand side of the comparison.
        - operation: The type of operation that will be used to perform the comparison.
    
    - Returns: A boolean value indicating whether the lhs is equal to the rhs based on the operator.
    
    - Complexity: O(*1*)
    */
    private func compare(lhs: String, rhs: String, operation: Operator) -> Bool {
        //Compare Data
        switch operation {
        case .equalTo:
            return lhs == rhs

        case .greaterThan:
            return lhs > rhs

        case .greaterThanOrEqualTo:
            return lhs >= rhs

        case .notEqualTo:
            return lhs != rhs

        case .lessThan:
            return lhs < rhs

        case .lessThanOrEqualTo:
            return lhs <= rhs

        default:
            return false
        }
    }

    /**
    Compares a single String value to another String value using the operation as a comparison type.
     
    - Parameters:
        - lhs: The value that will be used as the left-hand side of the comparison.
        - rhs: The value that will be used as the right-hand side of the comparison.
        - operation: The type of operation that will be used to perform the comparison.
    
    - Returns: A boolean value indicating whether the lhs is equal to the rhs based on the operator.
    
    - Complexity: O(*1*)
    */
    private func compareConditionWithOperator(lhs: String, rhs: String, operation: String) -> Bool {
        //Check Operator
        guard let operatorValue: Operator = Operator(rawValue: operation) else {
            return false
        }

        //Itterate Data
        switch operatorValue {
        case .equalTo:
            return lhs == rhs

        case .notEqualTo:
            return lhs != rhs

        case .greaterThan:
            return lhs > rhs

        case .lessThan:
            return lhs < rhs

        case .greaterThanOrEqualTo:
            return lhs >= rhs

        case .lessThanOrEqualTo:
            return lhs <= rhs

        case .and:
            return lhs.bool ?? false && rhs.bool ?? false

        case .or:
            return lhs.bool ?? false || rhs.bool ?? false
        }
    }

    /**
     
     */
    public func valueFor(condition: Condition) -> String? {
        switch condition {
        case .appVersion:
            return UIApplication.shared.appVersion

        case .buildNumber:
            return UIApplication.shared.buildNumber

        case .deviceModel:
            return UIDevice.current.modelName

        case .deviceName:
            return UIDevice.current.name

        case .deviceType:
            return UIDevice.current.deviceType

        case .deviceGeneration:
            return String(UIDevice.current.generation)

        case .operatingSystem:
            return "iOS"

        case .percentage:
            return String(self.cohortPercentage())

        case .systemVersion:
            return UIDevice.current.systemVersion
        }
    }
}

extension Character {
    var isNotOperandCharacter: Bool {
        if Operator(rawValue: String(self)) != nil {
            return true
        }
        return String(self) == ShuntingYardResolver.instance.leftToken || String(self) == ShuntingYardResolver.instance.rightToken
    }
}

extension String {
    var bool: Bool? {
        switch self.lowercased() {
        case "true", "t", "yes", "y", "1":
            return true
        case "false", "f", "no", "n", "0":
            return false
        default:
            return nil
        }
    }

    var isOperator: Bool {
        if let _: Operator = Operator(rawValue: self) {
            return true
        }
        return false
    }

    var isOperand: Bool {
        return !self.isOperator && self != ShuntingYardResolver.instance.leftToken && self != ShuntingYardResolver.instance.rightToken
    }

    var splitByTokens: [String] {
        //Setup Data
        var stack = Stack<Character>()
        let value: String = self
        var expressions: [String] = []

        //Tokenize
        value.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "&&", with: Operator.and.rawValue)
            .replacingOccurrences(of: "||", with: Operator.or.rawValue)
            .replacingOccurrences(of: "==", with: Operator.equalTo.rawValue)
            .replacingOccurrences(of: ">=", with: Operator.greaterThanOrEqualTo.rawValue)
            .replacingOccurrences(of: "<=", with: Operator.lessThanOrEqualTo.rawValue)
            .replacingOccurrences(of: "!=", with: Operator.notEqualTo.rawValue)
            .forEach { character in
                if character.isNotOperandCharacter {
                    expressions.append(ShuntingYardResolver.instance.getOperand(stack: stack))
                    stack.clear()
                    expressions.append(String(character))
                } else {
                    stack.push(character)
                }
        }

        //Check Data
        if stack.isNotEmpty {
            expressions.append(ShuntingYardResolver.instance.getOperand(stack: stack))
        }

        return expressions.filter { !$0.isEmpty }
    }
}
#endif
