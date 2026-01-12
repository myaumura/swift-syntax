//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Removes attributes from a syntax tree while maintaining their surrounding trivia.
@_spi(Testing)
public class NodeRemover: SyntaxRewriter {
  let predicate: (Syntax) -> Bool

  var triviaToAttachToNextToken: Trivia = Trivia()

  /// Initializes an attribute remover with a given predicate to determine which attributes to remove.
  ///
  /// - Parameter predicate: A closure that determines whether a given `AttributeSyntax` should be removed.
  ///   If this closure returns `true` for an attribute, that attribute will be removed.
  public init(removingWhere predicate: @escaping (Syntax) -> Bool) {
    self.predicate = predicate
    super.init(viewMode: .sourceAccurate)
  }

  public override func visit(_ node: AttributeListSyntax) -> AttributeListSyntax {
    var filteredAttributes: [AttributeListSyntax.Element] = []
    for attribute in node {
      guard case .attribute(let attribute) = attribute else {
        filteredAttributes.append(attribute)
        continue
      }
      if self.predicate(Syntax(attribute)) {
        var leadingTrivia = attribute.leadingTrivia

        // Don't leave behind an empty line when the attribute being removed is on its own line,
        // based on the following conditions:
        //  - Leading trivia ends with a newline followed by arbitrary number of spaces or tabs
        //  - All leading trivia pieces after the last newline are just whitespace, ensuring
        //    there are no comments or other non-whitespace characters on the same line
        //    preceding the attribute.
        //  - There is no trailing trivia and the next token has leading trivia.
        if let lastNewline = leadingTrivia.pieces.lastIndex(where: \.isNewline),
          leadingTrivia.pieces[lastNewline...].allSatisfy(\.isWhitespace),
          attribute.trailingTrivia.isEmpty,
          let nextToken = attribute.nextToken(viewMode: .sourceAccurate),
          !nextToken.leadingTrivia.isEmpty
        {
          leadingTrivia = Trivia(pieces: leadingTrivia.pieces[..<lastNewline])
        }

        // Drop any spaces or tabs from the trailing trivia because there’s no
        // more attribute they need to separate.
        let trailingTrivia = attribute.trailingTrivia.trimmingPrefix(while: \.isSpaceOrTab)
        triviaToAttachToNextToken += leadingTrivia + trailingTrivia

        // If the attribute is not separated from the previous attribute by trivia, as in
        // `@First@Second var x: Int` (yes, that's valid Swift), removing the `@Second`
        // attribute and dropping all its trivia would cause `@First` and `var` to join
        // without any trivia in between, which is invalid. In such cases, the trailing trivia
        // of the attribute is significant and must be retained.
        if triviaToAttachToNextToken.isEmpty,
          let previousToken = attribute.previousToken(viewMode: .sourceAccurate),
          previousToken.trailingTrivia.isEmpty
        {
          triviaToAttachToNextToken = attribute.trailingTrivia
        }
      } else {
        filteredAttributes.append(.attribute(prependAndClearAccumulatedTrivia(to: attribute)))
      }
    }

    // Ensure that any horizontal whitespace trailing the attributes list is trimmed if the next
    // token starts a new line.
    if let nextToken = node.nextToken(viewMode: .sourceAccurate),
      nextToken.leadingTrivia.startsWithNewline
    {
      if !triviaToAttachToNextToken.isEmpty {
        triviaToAttachToNextToken = triviaToAttachToNextToken.trimmingSuffix(while: \.isSpaceOrTab)
      } else if let lastAttribute = filteredAttributes.last {
        filteredAttributes[filteredAttributes.count - 1].trailingTrivia = lastAttribute
          .trailingTrivia
          .trimmingSuffix(while: \.isSpaceOrTab)
      }
    }
    return AttributeListSyntax(filteredAttributes)
  }

  public override func visit(_ node: DeclModifierListSyntax) -> DeclModifierListSyntax {
    var filteredModifiers: [DeclModifierListSyntax.Element] = []

    for modifier in node {
      if self.predicate(Syntax(modifier)) {
        let trailingTrivia = modifier.trailingTrivia.trimmingPrefix(while: \.isSpaceOrTab)
        triviaToAttachToNextToken += modifier.leadingTrivia.merging(trailingTrivia)

        if triviaToAttachToNextToken.isEmpty,
          let previousToken = modifier.previousToken(viewMode: .sourceAccurate),
          previousToken.trailingTrivia.isEmpty
        {
          triviaToAttachToNextToken = modifier.trailingTrivia
        }
      } else {
        filteredModifiers.append(prependAndClearAccumulatedTrivia(to: modifier))
      }
    }

    if !triviaToAttachToNextToken.isEmpty, !filteredModifiers.isEmpty {
      filteredModifiers[filteredModifiers.count - 1].trailingTrivia = filteredModifiers[filteredModifiers.count - 1]
        .trailingTrivia
        .merging(triviaToAttachToNextToken)
    }

    return DeclModifierListSyntax(filteredModifiers)
  }

  public override func visit(_ token: TokenSyntax) -> TokenSyntax {
    return prependAndClearAccumulatedTrivia(to: token)
  }

  /// Prepends the accumulated trivia to the given node's leading trivia.
  ///
  /// To preserve correct formatting after attribute removal, this function reassigns
  /// significant trivia accumulated from removed attributes to the provided subsequent node.
  /// Once attached, the accumulated trivia is cleared.
  ///
  /// - Parameter node: The syntax node receiving the accumulated trivia.
  /// - Returns: The modified syntax node with the prepended trivia.
  private func prependAndClearAccumulatedTrivia<T: SyntaxProtocol>(to syntaxNode: T) -> T {
    defer { triviaToAttachToNextToken = Trivia() }
    return syntaxNode.with(\.leadingTrivia, triviaToAttachToNextToken + syntaxNode.leadingTrivia)
  }
}

private extension Trivia {
  func trimmingPrefix(
    while predicate: (TriviaPiece) -> Bool
  ) -> Trivia {
    Trivia(pieces: self.drop(while: predicate))
  }

  func trimmingSuffix(
    while predicate: (TriviaPiece) -> Bool
  ) -> Trivia {
    Trivia(
      pieces: self[...]
        .reversed()
        .drop(while: predicate)
        .reversed()
    )
  }

  var startsWithNewline: Bool {
    self.first?.isNewline ?? false
  }
}
