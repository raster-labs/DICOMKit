import XCTest
@testable import DICOMNetwork

// MARK: - Bandwidth Configuration Tests

final class BandwidthConfigurationTests: XCTestCase {
    
    func test_init_withValidValues_createsConfiguration() {
        let config = BandwidthConfiguration(bytesPerSecond: 1_000_000, burstCapacity: 2_000_000)
        
        XCTAssertEqual(config.bytesPerSecond, 1_000_000)
        XCTAssertEqual(config.burstCapacity, 2_000_000)
        XCTAssertTrue(config.isEnabled)
    }
    
    func test_init_withDefaultBurst_usesBytesPerSecond() {
        let config = BandwidthConfiguration(bytesPerSecond: 1_000_000)
        
        XCTAssertEqual(config.burstCapacity, 1_000_000)
    }
    
    func test_init_withZeroBytes_disablesLimiting() {
        let config = BandwidthConfiguration(bytesPerSecond: 0)
        
        XCTAssertFalse(config.isEnabled)
    }
    
    func test_init_withNegativeBytes_treatsAsZero() {
        let config = BandwidthConfiguration(bytesPerSecond: -100)
        
        XCTAssertEqual(config.bytesPerSecond, 0)
        XCTAssertFalse(config.isEnabled)
    }
    
    func test_unlimited_isNotEnabled() {
        let config = BandwidthConfiguration.unlimited
        
        XCTAssertFalse(config.isEnabled)
        XCTAssertEqual(config.bytesPerSecond, 0)
    }
    
    func test_presets_haveExpectedValues() {
        XCTAssertEqual(BandwidthConfiguration.low.bytesPerSecond, 1_000_000)
        XCTAssertEqual(BandwidthConfiguration.medium.bytesPerSecond, 10_000_000)
        XCTAssertEqual(BandwidthConfiguration.high.bytesPerSecond, 100_000_000)
    }
    
    func test_megabytesPerSecond_convertsCorrectly() {
        let config = BandwidthConfiguration.megabytesPerSecond(5)
        
        XCTAssertEqual(config.bytesPerSecond, 5_000_000)
    }
    
    func test_kilobytesPerSecond_convertsCorrectly() {
        let config = BandwidthConfiguration.kilobytesPerSecond(500)
        
        XCTAssertEqual(config.bytesPerSecond, 500_000)
    }
    
    func test_description_showsUnlimited() {
        let config = BandwidthConfiguration.unlimited
        
        XCTAssertTrue(config.description.contains("unlimited"))
    }
    
    func test_description_showsRate() {
        let config = BandwidthConfiguration.megabytesPerSecond(10)
        
        XCTAssertTrue(config.description.contains("10.0"))
        XCTAssertTrue(config.description.contains("MB/s"))
    }
    
    func test_hashable_conformance() {
        let config1 = BandwidthConfiguration(bytesPerSecond: 1000)
        let config2 = BandwidthConfiguration(bytesPerSecond: 1000)
        let config3 = BandwidthConfiguration(bytesPerSecond: 2000)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
}

// MARK: - Bandwidth Statistics Tests

final class BandwidthStatisticsTests: XCTestCase {
    
    func test_statistics_containsAllFields() {
        let stats = BandwidthStatistics(
            totalBytesTransferred: 1000,
            bytesInCurrentWindow: 500,
            currentRateBytesPerSecond: 100,
            availableTokens: 200,
            throttleCount: 3,
            totalThrottleTime: 1.5
        )
        
        XCTAssertEqual(stats.totalBytesTransferred, 1000)
        XCTAssertEqual(stats.bytesInCurrentWindow, 500)
        XCTAssertEqual(stats.currentRateBytesPerSecond, 100)
        XCTAssertEqual(stats.availableTokens, 200)
        XCTAssertEqual(stats.throttleCount, 3)
        XCTAssertEqual(stats.totalThrottleTime, 1.5)
    }
}

// MARK: - Bandwidth Limiter Tests

final class BandwidthLimiterTests: XCTestCase {
    
    func test_init_setsConfiguration() async {
        let config = BandwidthConfiguration.megabytesPerSecond(10)
        let limiter = BandwidthLimiter(configuration: config)
        
        let currentConfig = await limiter.configuration
        XCTAssertEqual(currentConfig.bytesPerSecond, 10_000_000)
    }
    
    func test_unlimited_returnsUnlimitedConfiguration() async {
        let limiter = BandwidthLimiter.unlimited
        
        let config = await limiter.configuration
        XCTAssertFalse(config.isEnabled)
    }
    
    func test_acquire_withUnlimited_returnsImmediately() async {
        let limiter = BandwidthLimiter.unlimited
        
        let waitTime = await limiter.acquire(bytes: 1_000_000_000)
        
        XCTAssertEqual(waitTime, 0)
    }
    
    func test_acquire_withZeroBytes_returnsImmediately() async {
        let limiter = BandwidthLimiter(configuration: .low)
        
        let waitTime = await limiter.acquire(bytes: 0)
        
        XCTAssertEqual(waitTime, 0)
    }
    
    func test_tryAcquire_withAvailableTokens_succeeds() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        let limiter = BandwidthLimiter(configuration: config)
        
        let result = await limiter.tryAcquire(bytes: 500)
        
        XCTAssertTrue(result)
    }
    
    func test_tryAcquire_withInsufficientTokens_fails() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 100)
        let limiter = BandwidthLimiter(configuration: config)
        
        let result = await limiter.tryAcquire(bytes: 500)
        
        XCTAssertFalse(result)
    }
    
    func test_available_returnsCurrentTokens() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        let limiter = BandwidthLimiter(configuration: config)
        
        let available = await limiter.available()
        
        XCTAssertEqual(available, 1000)
    }
    
    func test_available_afterAcquire_decreases() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        let limiter = BandwidthLimiter(configuration: config)
        
        let consumption = await limiter.measuredAcquisition(bytes: 300)
        let sample = await limiter.measuredAvailability()

        assertReplenishment(sample, after: consumption, remaining: 700, configuration: config)
    }
    
    func test_estimatedWaitTime_withSufficientTokens_returnsZero() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        let limiter = BandwidthLimiter(configuration: config)
        
        let waitTime = await limiter.estimatedWaitTime(forBytes: 500)
        
        XCTAssertEqual(waitTime, 0)
    }
    
    func test_estimatedWaitTime_withInsufficientTokens_returnsPositive() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 100)
        let limiter = BandwidthLimiter(configuration: config)
        
        let waitTime = await limiter.estimatedWaitTime(forBytes: 500)
        
        XCTAssertGreaterThan(waitTime, 0)
    }
    
    func test_statistics_returnsValidData() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        let limiter = BandwidthLimiter(configuration: config)
        
        _ = await limiter.tryAcquire(bytes: 100)
        let stats = await limiter.statistics()
        
        XCTAssertEqual(stats.totalBytesTransferred, 100)
        XCTAssertEqual(stats.throttleCount, 0)
    }
    
    func test_reset_clearsStatistics() async {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        let limiter = BandwidthLimiter(configuration: config)
        
        _ = await limiter.tryAcquire(bytes: 500)
        await limiter.reset()
        
        let stats = await limiter.statistics()
        let available = await limiter.available()
        
        XCTAssertEqual(stats.totalBytesTransferred, 0)
        XCTAssertEqual(available, 1000)
    }
    
    func test_tokensReplenish_overTime() async throws {
        let config = BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 1000)
        // Include an observation later than the old fixed 200-token ceiling.
        for delay: UInt64 in [100_000_000, 250_000_000] {
            let limiter = BandwidthLimiter(configuration: config)
            let consumption = await limiter.measuredAcquisition(bytes: 1000)

            // Sleep allows replenishment, but does not impose a scheduler deadline.
            try await Task.sleep(nanoseconds: delay)

            let sample = await limiter.measuredAvailability()
            assertReplenishment(sample, after: consumption, remaining: 0, configuration: config)
        }
    }

    private func assertReplenishment(
        _ sample: (tokens: Int, before: Date, after: Date),
        after consumption: (acquired: Bool, before: Date, after: Date),
        remaining: Int,
        configuration: BandwidthConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(consumption.acquired, file: file, line: line)
        // Each production clock read lies inside its actor-isolated bracket.
        // Bound the expected byte count using elapsed time, rate and burst cap.
        let minimumElapsed = max(0, sample.before.timeIntervalSince(consumption.after))
        let maximumElapsed = max(0, sample.after.timeIntervalSince(consumption.before))
        let rate = Double(configuration.bytesPerSecond)
        let capacity = Double(configuration.burstCapacity)
        let lower = Int(min(capacity, Double(remaining) + minimumElapsed * rate).rounded(.down))
        let upper = Int(min(capacity, Double(remaining) + maximumElapsed * rate).rounded(.down))
        let diagnostic = "elapsed=\(minimumElapsed)...\(maximumElapsed)s; tokens=\(sample.tokens), expected=\(lower)...\(upper)"
        XCTAssertGreaterThanOrEqual(sample.tokens, lower, diagnostic, file: file, line: line)
        XCTAssertLessThanOrEqual(sample.tokens, upper, diagnostic, file: file, line: line)
    }
}

private extension BandwidthLimiter {
    func measuredAcquisition(bytes: Int) -> (acquired: Bool, before: Date, after: Date) {
        let before = Date()
        let acquired = tryAcquire(bytes: bytes)
        return (acquired, before, Date())
    }

    func measuredAvailability() -> (tokens: Int, before: Date, after: Date) {
        let before = Date()
        let tokens = available()
        return (tokens, before, Date())
    }
}

// MARK: - Bandwidth Schedule Period Tests

final class BandwidthSchedulePeriodTests: XCTestCase {
    
    func test_init_clampsHours() {
        let period = BandwidthSchedulePeriod(
            startHour: -5,
            startMinute: 0,
            endHour: 30,
            endMinute: 0,
            configuration: .unlimited
        )
        
        XCTAssertEqual(period.startHour, 0)
        XCTAssertEqual(period.endHour, 23)
    }
    
    func test_init_clampsMinutes() {
        let period = BandwidthSchedulePeriod(
            startHour: 10,
            startMinute: -10,
            endHour: 12,
            endMinute: 100,
            configuration: .unlimited
        )
        
        XCTAssertEqual(period.startMinute, 0)
        XCTAssertEqual(period.endMinute, 59)
    }
    
    func test_contains_withinPeriod_returnsTrue() {
        let period = BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            configuration: .unlimited
        )
        
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        components.hour = 12
        components.minute = 30
        let date = Calendar.current.date(from: components)!
        
        XCTAssertTrue(period.contains(date: date))
    }
    
    func test_contains_outsidePeriod_returnsFalse() {
        let period = BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            configuration: .unlimited
        )
        
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        components.hour = 20
        components.minute = 0
        let date = Calendar.current.date(from: components)!
        
        XCTAssertFalse(period.contains(date: date))
    }
    
    func test_contains_crossMidnight_works() {
        let period = BandwidthSchedulePeriod(
            startHour: 22,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            configuration: .unlimited
        )
        
        var lateComponents = DateComponents()
        lateComponents.year = 2024
        lateComponents.month = 1
        lateComponents.day = 15
        lateComponents.hour = 23
        lateComponents.minute = 30
        let lateDate = Calendar.current.date(from: lateComponents)!
        
        var earlyComponents = DateComponents()
        earlyComponents.year = 2024
        earlyComponents.month = 1
        earlyComponents.day = 16
        earlyComponents.hour = 4
        earlyComponents.minute = 0
        let earlyDate = Calendar.current.date(from: earlyComponents)!
        
        XCTAssertTrue(period.contains(date: lateDate))
        XCTAssertTrue(period.contains(date: earlyDate))
    }
    
    func test_contains_withDaysOfWeek_filtersCorrectly() {
        // Monday only (weekday 2)
        let period = BandwidthSchedulePeriod(
            startHour: 0,
            startMinute: 0,
            endHour: 23,
            endMinute: 59,
            daysOfWeek: [2],
            configuration: .unlimited
        )
        
        // A known Monday: January 15, 2024
        var mondayComponents = DateComponents()
        mondayComponents.year = 2024
        mondayComponents.month = 1
        mondayComponents.day = 15
        mondayComponents.hour = 12
        let monday = Calendar.current.date(from: mondayComponents)!
        
        // A known Tuesday: January 16, 2024
        var tuesdayComponents = DateComponents()
        tuesdayComponents.year = 2024
        tuesdayComponents.month = 1
        tuesdayComponents.day = 16
        tuesdayComponents.hour = 12
        let tuesday = Calendar.current.date(from: tuesdayComponents)!
        
        XCTAssertTrue(period.contains(date: monday))
        XCTAssertFalse(period.contains(date: tuesday))
    }
    
    func test_description_includesTimeRange() {
        let period = BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 30,
            endHour: 17,
            endMinute: 45,
            configuration: .unlimited
        )
        
        let description = period.description
        
        XCTAssertTrue(description.contains("09:30"))
        XCTAssertTrue(description.contains("17:45"))
    }
}

// MARK: - Bandwidth Schedule Tests

final class BandwidthScheduleTests: XCTestCase {
    
    func test_init_createsEmptySchedule() {
        let schedule = BandwidthSchedule()
        
        XCTAssertTrue(schedule.periods.isEmpty)
        XCTAssertFalse(schedule.defaultConfiguration.isEnabled) // unlimited is default
    }
    
    func test_addPeriod_addsToPeriods() {
        var schedule = BandwidthSchedule()
        
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            configuration: .low
        ))
        
        XCTAssertEqual(schedule.periods.count, 1)
    }
    
    func test_clearPeriods_removesAll() {
        var schedule = BandwidthSchedule()
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            configuration: .low
        ))
        
        schedule.clearPeriods()
        
        XCTAssertTrue(schedule.periods.isEmpty)
    }
    
    func test_activeConfiguration_withinPeriod_returnsPeriodConfig() {
        var schedule = BandwidthSchedule(defaultConfiguration: .unlimited)
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 0,
            startMinute: 0,
            endHour: 23,
            endMinute: 59,
            configuration: .low
        ))
        
        let config = schedule.activeConfiguration()
        
        XCTAssertEqual(config.bytesPerSecond, BandwidthConfiguration.low.bytesPerSecond)
    }
    
    func test_isScheduledPeriodActive_withinPeriod_returnsTrue() {
        var schedule = BandwidthSchedule()
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 0,
            startMinute: 0,
            endHour: 23,
            endMinute: 59,
            configuration: .low
        ))
        
        XCTAssertTrue(schedule.isScheduledPeriodActive())
    }
    
    func test_businessHours_preset_hasCorrectStructure() {
        let schedule = BandwidthSchedule.businessHours()
        
        XCTAssertEqual(schedule.periods.count, 1)
        XCTAssertFalse(schedule.defaultConfiguration.isEnabled) // Unlimited outside hours
    }
    
    func test_offPeak_preset_hasCorrectStructure() {
        let schedule = BandwidthSchedule.offPeak()
        
        XCTAssertEqual(schedule.periods.count, 1)
        XCTAssertTrue(schedule.defaultConfiguration.isEnabled) // Limited by default
    }
    
    func test_description_showsPeriodCount() {
        var schedule = BandwidthSchedule()
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            configuration: .low
        ))
        
        let description = schedule.description
        
        XCTAssertTrue(description.contains("1 periods"))
    }
}

// MARK: - Scheduled Bandwidth Limiter Tests

final class ScheduledBandwidthLimiterTests: XCTestCase {
    
    func test_init_usesScheduleConfiguration() async {
        var schedule = BandwidthSchedule(defaultConfiguration: .low)
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 0,
            startMinute: 0,
            endHour: 23,
            endMinute: 59,
            configuration: .high
        ))
        
        let limiter = ScheduledBandwidthLimiter(schedule: schedule)
        
        let config = await limiter.activeConfiguration()
        XCTAssertEqual(config.bytesPerSecond, BandwidthConfiguration.high.bytesPerSecond)
    }
    
    func test_acquire_usesCurrentConfiguration() async {
        let schedule = BandwidthSchedule(defaultConfiguration: .unlimited)
        let limiter = ScheduledBandwidthLimiter(schedule: schedule)
        
        let waitTime = await limiter.acquire(bytes: 1_000_000)
        
        XCTAssertEqual(waitTime, 0) // Unlimited should be immediate
    }
    
    func test_tryAcquire_usesCurrentConfiguration() async {
        var schedule = BandwidthSchedule()
        schedule.addPeriod(BandwidthSchedulePeriod(
            startHour: 0,
            startMinute: 0,
            endHour: 23,
            endMinute: 59,
            configuration: BandwidthConfiguration(bytesPerSecond: 1000, burstCapacity: 500)
        ))
        
        let limiter = ScheduledBandwidthLimiter(schedule: schedule)
        
        let result = await limiter.tryAcquire(bytes: 1000)
        
        XCTAssertFalse(result) // Burst capacity too small
    }
    
    func test_statistics_returnsValidData() async {
        let schedule = BandwidthSchedule(defaultConfiguration: .unlimited)
        let limiter = ScheduledBandwidthLimiter(schedule: schedule)
        
        _ = await limiter.acquire(bytes: 100)
        let stats = await limiter.statistics()
        
        XCTAssertEqual(stats.totalBytesTransferred, 100)
    }
}
