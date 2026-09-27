//
//  DeviceHardwareService.swift
//  TruelyOpen.AI
//
//  Created by Aryan Sharma on 21/09/26.
//

import Foundation
import Darwin
import UIKit
import Combine
import SwiftUI

public final class DeviceHardwareService: ObservableObject {
    public static let shared = DeviceHardwareService()

    @Published public private(set) var physicalMemoryGB: Double = 0.0
    @Published public private(set) var usedMemoryGB: Double = 0.0
    @Published public private(set) var availableMemoryGB: Double = 0.0
    @Published public private(set) var memoryUsageRatio: Double = 0.0
    @Published public private(set) var deviceModelName: String = ""

    private var timer: Timer?

    private init() {
        self.physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        self.deviceModelName = getDeviceModelIdentifier()
        updateMemoryMetrics()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.updateMemoryMetrics()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    public func updateMemoryMetrics() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            let usedBytes = Double(info.resident_size)
            let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
            let usedGB = usedBytes / (1024 * 1024 * 1024)
            let availableGB = (totalBytes - usedBytes) / (1024 * 1024 * 1024)

            DispatchQueue.main.async {
                self.usedMemoryGB = usedGB
                self.availableMemoryGB = max(availableGB, 0)
                self.memoryUsageRatio = min(max(usedBytes / totalBytes, 0), 1)
            }
        }
    }

    private func getDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}
