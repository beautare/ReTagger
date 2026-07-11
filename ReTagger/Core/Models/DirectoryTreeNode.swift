//
//  DirectoryTreeNode.swift
//  ReTagger
//
//  Directory tree data structure for Finder-style navigation
//

import Foundation
import Combine

/// Represents a node in the directory tree
class DirectoryTreeNode: Identifiable, ObservableObject, Equatable {
    static func == (lhs: DirectoryTreeNode, rhs: DirectoryTreeNode) -> Bool {
        lhs === rhs
    }

    let id = UUID()
    let url: URL
    let name: String
    @Published var children: [DirectoryTreeNode]?
    @Published var isExpanded: Bool = false

    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
    }

    /// Load child directories
    /// 注意：调用者必须确保已通过 AppCoordinator.activateSecurityScope 激活目录权限
    func loadChildren(force: Bool = false) {
        guard isDirectory else { return }
        guard force || children == nil else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            self.children = contents
                .filter { url in
                    guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                          let isDirectory = resourceValues.isDirectory else {
                        return false
                    }
                    return isDirectory
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { DirectoryTreeNode(url: $0) }

        } catch {
            print("⚠️ Failed to load children for \(url.path): \(error.localizedDescription)")
            self.children = []
        }
    }

    /// Toggle expansion state
    func toggleExpanded() {
        if children == nil {
            loadChildren()
        }
        isExpanded.toggle()
    }

    /// Expand the directory tree to reveal the target URL within this node's hierarchy.
    func expand(to targetURL: URL) {
        guard targetURL.isSameOrDescendant(of: url) else { return }
        guard url != targetURL else { return }

        if children == nil {
            loadChildren()
        }

        isExpanded = true

        guard let children = children else { return }
        for child in children {
            if targetURL.isSameOrDescendant(of: child.url) {
                child.expand(to: targetURL)
                break
            }
        }
    }
}
