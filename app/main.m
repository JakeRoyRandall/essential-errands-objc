#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <limits.h>

static void Fail(NSString *message) { fprintf(stderr, "error: %s\n", message.UTF8String); exit(2); }
static void PrintCSVRow(NSArray<NSString *> *fields) {
    NSMutableString *line = [NSMutableString string];
    for (NSUInteger i = 0; i < fields.count; i++) {
        NSString *value = fields[i] ?: @"";
        [line appendFormat:@"\"%@\"%@", [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""], i + 1 == fields.count ? @"" : @","];
    }
    printf("%s\r\n", line.UTF8String);
}
static NSDictionary *ScheduleTasks(NSArray *inputTasks, NSString *orderMode, NSString *startingID, BOOL hasUntil, long long until, BOOL hasBreakAfter, long long breakAfter, long long breakFor, long long startOffset) {
    NSMutableArray *tasks = [inputTasks mutableCopy];
    [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSComparisonResult result = [orderMode isEqualToString:@"shortest"] ? [a[@"minutes"] compare:b[@"minutes"]] : [a[@"deadline"] compare:b[@"deadline"]]; if (result != NSOrderedSame) return result; if ([orderMode isEqualToString:@"shortest"]) { result = [a[@"deadline"] compare:b[@"deadline"]]; if (result != NSOrderedSame) return result; } result = [b[@"priority"] compare:a[@"priority"]]; return result == NSOrderedSame ? [a[@"order"] compare:b[@"order"]] : result; }];
    NSMutableArray *events = [NSMutableArray array], *remaining = [tasks mutableCopy], *deferred = [NSMutableArray array]; long long clock = startOffset, sinceBreak = 0, totalService = 0, totalBreak = 0, totalIdle = 0, totalWait = 0, maxLate = 0, deadlineMisses = 0; BOOL firstStop = YES;
    while (remaining.count > 0) {
        if (!firstStop && hasBreakAfter && sinceBreak >= breakAfter) {
            if (hasUntil && clock + breakFor > until) { [deferred addObjectsFromArray:[remaining valueForKey:@"id"]]; break; }
            long long end = clock + breakFor; [events addObject:@{ @"kind": @"break", @"start": @(clock), @"finish": @(end), @"lateness": @0 }]; clock = end; totalBreak += breakFor; sinceBreak = 0;
        }
        NSUInteger selected = NSNotFound;
        if (firstStop && startingID) selected = [remaining indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) { return [task[@"id"] isEqualToString:startingID]; }];
        else selected = [remaining indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) { return [task[@"release"] longLongValue] <= clock && (!hasUntil || clock + [task[@"minutes"] longLongValue] <= until); }];
        if (firstStop && startingID && selected != NSNotFound && hasUntil) { long long forcedStart = MAX(clock, [remaining[selected][@"release"] longLongValue]); if (forcedStart + [remaining[selected][@"minutes"] longLongValue] > until) Fail(@"--from errand cannot finish by --until"); }
        if (selected == NSNotFound) {
            long long next = LLONG_MAX; for (NSDictionary *candidate in remaining) if ([candidate[@"release"] longLongValue] > clock) next = MIN(next, [candidate[@"release"] longLongValue]);
            if (hasUntil && (next == LLONG_MAX || next > until)) { [deferred addObjectsFromArray:[remaining valueForKey:@"id"]]; break; }
            [events addObject:@{ @"kind": @"idle", @"start": @(clock), @"finish": @(next), @"lateness": @0 }]; totalIdle += next - clock; clock = next; continue;
        }
        NSDictionary *task = remaining[selected]; [remaining removeObjectAtIndex:selected]; long long release = [task[@"release"] longLongValue];
        if (clock < release) { [events addObject:@{ @"kind": @"idle", @"start": @(clock), @"finish": @(release), @"lateness": @0 }]; totalIdle += release - clock; clock = release; }
        long long start = clock, service = [task[@"minutes"] longLongValue]; clock += service; totalService += service; sinceBreak += service; totalWait += start - release; long long late = MAX(0, clock - [task[@"deadline"] longLongValue]); maxLate = MAX(maxLate, late); if (late > 0) deadlineMisses++;
        [events addObject:@{ @"kind": @"errand", @"id": task[@"id"], @"name": task[@"name"], @"release": @(release), @"priority": task[@"priority"], @"start": @(start), @"finish": @(clock), @"lateness": @(late) }]; firstStop = NO;
    }
    NSUInteger scheduled = tasks.count - deferred.count; double average = scheduled == 0 ? 0.0 : (double)totalWait / (double)scheduled;
    return @{ @"events": events, @"deferred": deferred, @"scheduled_count": @(scheduled), @"total_service": @(totalService), @"total_break_time": @(totalBreak), @"total_idle_time": @(totalIdle), @"finish": @(clock), @"max_lateness": @(maxLate), @"deadline_misses": @(deadlineMisses), @"average_wait_after_release": @(average) };
}
static BOOL ValidInteger(id value, long long *out) {
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    if (!isfinite(number) || floor(number) != number || number < 0 || number > 1000000) return NO;
    *out = [value longLongValue]; return YES;
}
static NSData *ReadInput(NSString *path) {
    FILE *input = stdin;
    if (path.length > 0 && ![path isEqualToString:@"-"]) {
        input = fopen(path.UTF8String, "rb");
        if (!input) Fail(@"cannot read input file");
    }
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096]; size_t count = 0;
    while ((count = fread(buffer, 1, sizeof buffer, input)) > 0) {
        if (data.length + count > 1024 * 1024) Fail(@"input exceeds 1 MiB");
        [data appendBytes:buffer length:count];
    }
    BOOL readFailed = ferror(input) != 0;
    if (input != stdin) fclose(input);
    if (readFailed) Fail(@"cannot read input");
    return data;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *inputPath = @"-", *startingID = nil, *orderMode = @"edf"; NSMutableArray *skipIDs = [NSMutableArray array]; BOOL hasInput = NO, jsonOutput = NO, csvOutput = NO, statsOutput = NO, hasUntil = NO, compareOutput = NO, explicitOrder = NO; long long startOffset = 0, breakAfter = 0, breakFor = 0, until = 0; BOOL hasBreakAfter = NO, hasBreakFor = NO;
        for (int i = 1; i < argc; i++) { NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--from"]) {
                if (++i >= argc) Fail(@"--from requires an errand id");
                startingID = [NSString stringWithUTF8String:argv[i]];
                if (startingID.length == 0) Fail(@"--from requires an errand id");
            } else if ([arg isEqualToString:@"--skip"]) {
                if (++i >= argc) Fail(@"--skip requires an errand id"); NSString *skipID = [NSString stringWithUTF8String:argv[i]];
                if (skipID.length == 0) Fail(@"--skip requires an errand id");
                if (![skipIDs containsObject:skipID]) [skipIDs addObject:skipID];
                if (skipIDs.count > 100) Fail(@"at most 100 skipped IDs are supported");
            } else if ([arg isEqualToString:@"--until"]) {
                if (++i >= argc) Fail(@"--until requires an integer value"); NSString *value = [NSString stringWithUTF8String:argv[i]]; NSScanner *scanner = [NSScanner scannerWithString:value];
                if (![scanner scanLongLong:&until] || !scanner.isAtEnd || until < 0 || until > 1000000) Fail(@"--until value is out of bounds"); hasUntil = YES;
            } else if ([arg isEqualToString:@"--start"] || [arg isEqualToString:@"--break-after"] || [arg isEqualToString:@"--break-for"]) {
                if (++i >= argc) Fail(@"option requires an integer value"); NSString *value = [NSString stringWithUTF8String:argv[i]]; NSScanner *scanner = [NSScanner scannerWithString:value]; long long number = 0;
                if (![scanner scanLongLong:&number] || !scanner.isAtEnd || number < 0 || number > 1000000 || ([arg isEqualToString:@"--break-after"] && number == 0) || ([arg isEqualToString:@"--break-for"] && number == 0)) Fail(@"option value is out of bounds");
                if ([arg isEqualToString:@"--start"]) startOffset = number; else if ([arg isEqualToString:@"--break-after"]) { breakAfter = number; hasBreakAfter = YES; } else { breakFor = number; hasBreakFor = YES; }
            } else if ([arg isEqualToString:@"--json"]) jsonOutput = YES;
            else if ([arg isEqualToString:@"--csv"]) csvOutput = YES;
            else if ([arg isEqualToString:@"--stats"]) statsOutput = YES;
            else if ([arg isEqualToString:@"--compare"]) compareOutput = YES;
            else if ([arg isEqualToString:@"--order"]) {
                if (++i >= argc) Fail(@"--order requires edf or shortest"); orderMode = [NSString stringWithUTF8String:argv[i]];
                if (![orderMode isEqualToString:@"edf"] && ![orderMode isEqualToString:@"shortest"]) Fail(@"--order must be edf or shortest");
                explicitOrder = YES;
            }
            else if ([arg hasPrefix:@"-"] && ![arg isEqualToString:@"-"]) Fail(@"unknown option"); else if (hasInput) Fail(@"only one input file is allowed"); else { inputPath = arg; hasInput = YES; }
        }
        if (jsonOutput && csvOutput) Fail(@"--json and --csv are mutually exclusive");
        if (csvOutput && statsOutput) Fail(@"--stats cannot be combined with --csv");
        if (compareOutput && explicitOrder) Fail(@"--compare cannot be combined with --order");
        if (compareOutput && csvOutput) Fail(@"--compare cannot be combined with --csv");
        if (hasBreakAfter != hasBreakFor) Fail(@"--break-after and --break-for must be paired");
        NSData *data = ReadInput(inputPath); NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error || ![parsed isKindOfClass:[NSArray class]]) Fail(@"input must be a JSON array");
        NSArray *items = parsed; if (items.count > 100) Fail(@"at most 100 errands are supported");
        NSMutableSet *ids = [NSMutableSet set]; NSMutableArray *tasks = [NSMutableArray array]; NSUInteger order = 0;
        for (id raw in items) {
            if (![raw isKindOfClass:[NSDictionary class]]) Fail(@"each errand must be an object");
            NSString *taskID = raw[@"id"]; NSString *name = raw[@"name"]; long long minutes = 0, deadline = 0, release = 0, priority = 0;
            if (![taskID isKindOfClass:[NSString class]] || taskID.length == 0 || taskID.length > 64 || [taskID rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || [ids containsObject:taskID]) Fail(@"ids must be unique strings up to 64 safe characters");
            if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 120 || [name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || !ValidInteger(raw[@"minutes"], &minutes) || !ValidInteger(raw[@"deadline"], &deadline) || (raw[@"release"] != nil && !ValidInteger(raw[@"release"], &release)) || (raw[@"priority"] != nil && (!ValidInteger(raw[@"priority"], &priority) || priority > 9))) Fail(@"name, minutes, deadline, release, and optional priority have invalid types or bounds");
            [ids addObject:taskID]; [tasks addObject:@{ @"id": taskID, @"name": name, @"minutes": @(minutes), @"deadline": @(deadline), @"release": @(release), @"priority": @(priority), @"order": @(order++) }];
        }
        for (NSString *skipID in skipIDs) if (![ids containsObject:skipID]) Fail(@"--skip id was not found in input");
        if (startingID && [skipIDs containsObject:startingID]) Fail(@"--from id cannot also be skipped");
        NSMutableArray *skipped = [NSMutableArray array]; NSMutableArray *planned = [NSMutableArray array];
        for (NSDictionary *task in tasks) { if ([skipIDs containsObject:task[@"id"]]) [skipped addObject:task[@"id"]]; else [planned addObject:task]; }
        tasks = planned;
        [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSComparisonResult result = [orderMode isEqualToString:@"shortest"] ? [a[@"minutes"] compare:b[@"minutes"]] : [a[@"deadline"] compare:b[@"deadline"]]; if (result != NSOrderedSame) return result; if ([orderMode isEqualToString:@"shortest"]) { result = [a[@"deadline"] compare:b[@"deadline"]]; if (result != NSOrderedSame) return result; } result = [b[@"priority"] compare:a[@"priority"]]; return result == NSOrderedSame ? [a[@"order"] compare:b[@"order"]] : result; }];
        if (startingID && [tasks indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) { return [task[@"id"] isEqualToString:startingID]; }] == NSNotFound) Fail(@"--from id was not found in input");
        if (hasUntil && startOffset > until) Fail(@"--start cannot be after --until");
        if (compareOutput) {
            NSMutableDictionary *comparison = [NSMutableDictionary dictionary];
            for (NSString *policy in @[@"edf", @"shortest"]) { NSDictionary *metrics = ScheduleTasks(tasks, policy, startingID, hasUntil, until, hasBreakAfter, breakAfter, breakFor, startOffset); comparison[policy] = @{ @"scheduled": metrics[@"scheduled_count"], @"missed": metrics[@"deadline_misses"], @"max_lateness": metrics[@"max_lateness"], @"finish": metrics[@"finish"], @"average_wait": metrics[@"average_wait_after_release"] }; }
            if (jsonOutput) { NSDictionary *output = @{ @"schema_version": @1, @"comparison": comparison }; NSError *jsonError = nil; NSData *encoded = [NSJSONSerialization dataWithJSONObject:output options:0 error:&jsonError]; if (!encoded || jsonError || fwrite(encoded.bytes, 1, encoded.length, stdout) != encoded.length || putchar('\n') == EOF) Fail(@"cannot write comparison JSON"); }
            else { printf("COMPARE\tmetric\tedf\tshortest\n"); for (NSString *metric in @[@"scheduled", @"missed", @"max_lateness", @"finish", @"average_wait"]) printf("COMPARE\t%s\t%s\t%s\n", metric.UTF8String, [comparison[@"edf"][metric] description].UTF8String, [comparison[@"shortest"][metric] description].UTF8String); }
            return 0;
        }
        NSDictionary *schedule = ScheduleTasks(tasks, orderMode, startingID, hasUntil, until, hasBreakAfter, breakAfter, breakFor, startOffset);
        NSArray *scheduleEvents = schedule[@"events"], *scheduleDeferred = schedule[@"deferred"];
        if (csvOutput) PrintCSVRow(@[@"kind", @"id", @"name", @"start", @"finish", @"lateness"]); else if (!jsonOutput) printf("id\tname\tstart\tfinish\tlateness\n");
        for (NSDictionary *event in scheduleEvents) { NSString *kind = event[@"kind"]; if (csvOutput) { if ([kind isEqualToString:@"errand"]) PrintCSVRow(@[@"errand", event[@"id"], event[@"name"], [event[@"start"] description], [event[@"finish"] description], [event[@"lateness"] description]]); else PrintCSVRow(@[kind, @"", kind, [event[@"start"] description], [event[@"finish"] description], @"0"]); } else if (!jsonOutput) { if ([kind isEqualToString:@"errand"]) printf("%s\t%s\t%s\t%s\t%s\n", [event[@"id"] UTF8String], [event[@"name"] UTF8String], [event[@"start"] description].UTF8String, [event[@"finish"] description].UTF8String, [event[@"lateness"] description].UTF8String); else printf("%s\t%s\t%s\t%s\t0\n", kind.uppercaseString.UTF8String, kind.UTF8String, [event[@"start"] description].UTF8String, [event[@"finish"] description].UTF8String); } }
        if (csvOutput) for (NSString *taskID in skipped) PrintCSVRow(@[@"skipped", taskID, @"", @"", @"", @""]); else if (!jsonOutput) for (NSString *taskID in skipped) printf("SKIPPED\t%s\n", taskID.UTF8String);
        if (csvOutput) for (NSString *taskID in scheduleDeferred) PrintCSVRow(@[@"deferred", taskID, @"", @"", @"", @""]); else if (!jsonOutput) for (NSString *taskID in scheduleDeferred) printf("DEFERRED\t%s\n", taskID.UTF8String);
        if (jsonOutput) { NSMutableDictionary *result = [@{ @"schema_version": @1, @"order": orderMode, @"start": @(startOffset), @"events": scheduleEvents, @"total_service": schedule[@"total_service"], @"total_break_time": schedule[@"total_break_time"], @"total_idle_time": schedule[@"total_idle_time"], @"finish": schedule[@"finish"], @"max_lateness": schedule[@"max_lateness"], @"deadline_misses": schedule[@"deadline_misses"], @"scheduled_count": schedule[@"scheduled_count"], @"deferred_count": @(scheduleDeferred.count), @"skipped_count": @(skipped.count), @"average_wait_after_release": schedule[@"average_wait_after_release"], @"skipped": skipped, @"deferred": scheduleDeferred } mutableCopy]; if (hasUntil) result[@"until"] = @(until); NSError *jsonError = nil; NSData *output = [NSJSONSerialization dataWithJSONObject:result options:0 error:&jsonError]; if (!output || jsonError || fwrite(output.bytes, 1, output.length, stdout) != output.length || putchar('\n') == EOF) Fail(@"cannot write JSON output"); }
        if (!jsonOutput && statsOutput) printf("STATS\tscheduled=%s\tdeferred=%lu\tskipped=%lu\tservice=%s\tbreak=%s\tidle=%s\tfinish=%s\tmax-lateness=%s\tdeadline-misses=%s\taverage-wait-after-release=%.3f\n", [schedule[@"scheduled_count"] description].UTF8String, (unsigned long)scheduleDeferred.count, (unsigned long)skipped.count, [schedule[@"total_service"] description].UTF8String, [schedule[@"total_break_time"] description].UTF8String, [schedule[@"total_idle_time"] description].UTF8String, [schedule[@"finish"] description].UTF8String, [schedule[@"max_lateness"] description].UTF8String, [schedule[@"deadline_misses"] description].UTF8String, [schedule[@"average_wait_after_release"] doubleValue]);
        return 0;
    }
    return 0;
}
