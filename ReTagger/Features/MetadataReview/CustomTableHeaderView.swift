//
//  CustomTableHeaderView.swift
//  ReTagger
//
//  Created by Claude Code
//

import AppKit

protocol CustomTableHeaderViewDelegate: AnyObject {
    func headerView(_ headerView: CustomTableHeaderView, didDoubleClickSeparatorAt columnIndex: Int)
}

final class CustomTableHeaderView: NSTableHeaderView {
    weak var customDelegate: CustomTableHeaderViewDelegate?
    
    override func mouseDown(with event: NSEvent) {
        // Handle double click
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            
            guard let tableView = tableView else {
                super.mouseDown(with: event)
                return
            }
            
            // Use headerRect(ofColumn:) which accounts for scrolling and position
            for i in 0..<tableView.tableColumns.count {
                let rect = headerRect(ofColumn: i)
                
                // If rect is empty, column might be hidden or offscreen logic
                if rect.isEmpty { continue }
                
                // Separator is at the right edge of the column header
                // Hit test zone: +/- 4 points from the edge
                let separatorX = rect.maxX
                let separatorZone = (separatorX - 4)...(separatorX + 4)
                
                if separatorZone.contains(point.x) {
                    customDelegate?.headerView(self, didDoubleClickSeparatorAt: i)
                    return // Consume the event
                }
            }
        }
        
        super.mouseDown(with: event)
    }
}
