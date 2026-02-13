//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftParser
import SwiftRefactor
import SwiftSyntax
import SwiftSyntaxBuilder
import XCTest
import _SwiftSyntaxTestSupport

final class MoveMembersToExtensionTests: XCTestCase {
  func testMoveFunctionToExtension() throws {
    let baseline: SourceFileSyntax = """
      class Foo {
        func foo() {
          print("Hello world!")
        }

        func bar() {
          print("Hello world!")
        }
      }
      """

    let expected: SourceFileSyntax = """
      class Foo {

        func bar() {
          print("Hello world!")
        }
      }

      extension Foo {
        func foo() {
          print("Hello world!")
        }
      }
      """

    let context = MoveMembersToExtension.Context(
      range: AbsolutePosition(utf8Offset: 11)..<AbsolutePosition(utf8Offset: 56)
    )
    try assertRefactorConvert(baseline, expected: expected, context: context)
  }

  func testMoveFunctionToExtension2() throws {
    let baseline: SourceFileSyntax = """
      class Foo {
        func foo() {
          print("Hello world!")
        }

        func bar() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }
      """

    let expected: SourceFileSyntax = """
      class Foo {

        func bar() {
          print("Hello world!")
        }
      }

      extension Foo {
        func foo() {
          print("Hello world!")
        }
      }

      struct Bar {
        func foo() {}
      }
      """

    let context = MoveMembersToExtension.Context(
      range: AbsolutePosition(utf8Offset: 11)..<AbsolutePosition(utf8Offset: 56)
    )
    try assertRefactorConvert(baseline, expected: expected, context: context)
  }

  func testNested() throws {
    let baseline: SourceFileSyntax = """
      struct Outer {
        struct Inner {
          func moveThis() {}
        }
      }
      """

    let expected: SourceFileSyntax = """
      struct Outer {
      }

      extension Outer {
        struct Inner {
          func moveThis() {}
        }
      }
      """

    let context = MoveMembersToExtension.Context(
      range: AbsolutePosition(utf8Offset: 14)..<AbsolutePosition(utf8Offset: 58)
    )
    try assertRefactorConvert(baseline, expected: expected, context: context)
  }
}

private func assertRefactorConvert(
  _ callDecl: SourceFileSyntax,
  expected: SourceFileSyntax?,
  context: MoveMembersToExtension.Context,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  try assertRefactor(
    callDecl,
    context: context,
    provider: MoveMembersToExtension.self,
    expected: expected,
    file: file,
    line: line
  )
}
