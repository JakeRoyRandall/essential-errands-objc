#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <limits.h>

static void Fail(NSString *message) { fprintf(stderr, "error: %s\n", message.UTF8String); exit(2); }
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
        NSString *inputPath = @"-", *startingID = nil; BOOL hasInput = NO, jsonOutput = NO; long long startOffset = 0, breakAfter = 0, breakFor = 0; BOOL hasBreakAfter = NO, hasBreakFor = NO;
        for (int i = 1; i < argc; i++) { NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--from"]) {
                if (++i >= argc) Fail(@"--from requires an errand id");
                startingID = [NSString stringWithUTF8String:argv[i]];
                if (startingID.length == 0) Fail(@"--from requires an errand id");
            } else if ([arg isEqualToString:@"--start"] || [arg isEqualToString:@"--break-after"] || [arg isEqualToString:@"--break-for"]) {
                if (++i >= argc) Fail(@"option requires an integer value"); NSString *value = [NSString stringWithUTF8String:argv[i]]; NSScanner *scanner = [NSScanner scannerWithString:value]; long long number = 0;
                if (![scanner scanLongLong:&number] || !scanner.isAtEnd || number < 0 || number > 1000000 || ([arg isEqualToString:@"--break-after"] && number == 0) || ([arg isEqualToString:@"--break-for"] && number == 0)) Fail(@"option value is out of bounds");
                if ([arg isEqualToString:@"--start"]) startOffset = number; else if ([arg isEqualToString:@"--break-after"]) { breakAfter = number; hasBreakAfter = YES; } else { breakFor = number; hasBreakFor = YES; }
            } else if ([arg isEqualToString:@"--json"]) jsonOutput = YES;
            else if ([arg hasPrefix:@"-"] && ![arg isEqualToString:@"-"]) Fail(@"unknown option"); else if (hasInput) Fail(@"only one input file is allowed"); else { inputPath = arg; hasInput = YES; }
        }
        if (hasBreakAfter != hasBreakFor) Fail(@"--break-after and --break-for must be paired");
        NSData *data = ReadInput(inputPath); NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error || ![parsed isKindOfClass:[NSArray class]]) Fail(@"input must be a JSON array");
        NSArray *items = parsed; if (items.count > 100) Fail(@"at most 100 errands are supported");
        NSMutableSet *ids = [NSMutableSet set]; NSMutableArray *tasks = [NSMutableArray array]; NSUInteger order = 0;
        for (id raw in items) {
            if (![raw isKindOfClass:[NSDictionary class]]) Fail(@"each errand must be an object");
            NSString *taskID = raw[@"id"]; NSString *name = raw[@"name"]; long long minutes = 0, deadline = 0, release = 0;
            if (![taskID isKindOfClass:[NSString class]] || taskID.length == 0 || taskID.length > 64 || [taskID rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || [ids containsObject:taskID]) Fail(@"ids must be unique strings up to 64 safe characters");
            if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 120 || [name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || !ValidInteger(raw[@"minutes"], &minutes) || !ValidInteger(raw[@"deadline"], &deadline) || (raw[@"release"] != nil && !ValidInteger(raw[@"release"], &release))) Fail(@"name, minutes, deadline, and optional release have invalid types or bounds");
            [ids addObject:taskID]; [tasks addObject:@{ @"id": taskID, @"name": name, @"minutes": @(minutes), @"deadline": @(deadline), @"release": @(release), @"order": @(order++) }];
        }
        [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSComparisonResult result = [a[@"deadline"] compare:b[@"deadline"]]; return result == NSOrderedSame ? [a[@"order"] compare:b[@"order"]] : result; }];
        if (startingID && [tasks indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) { return [task[@"id"] isEqualToString:startingID]; }] == NSNotFound) Fail(@"--from id was not found in input");
        if (!jsonOutput) printf("id\tname\tstart\tfinish\tlateness\n");
        NSMutableArray *events = [NSMutableArray array]; NSMutableArray *remaining = [tasks mutableCopy]; long long clock = startOffset, sinceBreak = 0, totalService = 0, totalBreak = 0, totalIdle = 0, maxLate = 0; BOOL firstStop = YES;
        while (remaining.count > 0) {
            if (!firstStop && hasBreakAfter && sinceBreak >= breakAfter) {
                long long breakEnd = clock + breakFor;
                if (!jsonOutput) printf("BREAK\tbreak\t%lld\t%lld\t0\n", clock, breakEnd); else [events addObject:@{ @"kind": @"break", @"start": @(clock), @"finish": @(breakEnd), @"lateness": @0 }];
                clock = breakEnd; totalBreak += breakFor; sinceBreak = 0;
            }
            NSUInteger selected = NSNotFound;
            if (firstStop && startingID) selected = [remaining indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) { return [task[@"id"] isEqualToString:startingID]; }];
            else selected = [remaining indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) { return [task[@"release"] longLongValue] <= clock; }];
            if (selected == NSNotFound) {
                long long nextRelease = LLONG_MAX;
                for (NSDictionary *candidate in remaining) nextRelease = MIN(nextRelease, [candidate[@"release"] longLongValue]);
                if (!jsonOutput) printf("IDLE\tidle\t%lld\t%lld\t0\n", clock, nextRelease); else [events addObject:@{ @"kind": @"idle", @"start": @(clock), @"finish": @(nextRelease), @"lateness": @0 }];
                totalIdle += nextRelease - clock; clock = nextRelease; continue;
            }
            NSDictionary *task = remaining[selected]; [remaining removeObjectAtIndex:selected];
            long long release = [task[@"release"] longLongValue]; if (clock < release) { if (!jsonOutput) printf("IDLE\tidle\t%lld\t%lld\t0\n", clock, release); else [events addObject:@{ @"kind": @"idle", @"start": @(clock), @"finish": @(release), @"lateness": @0 }]; totalIdle += release - clock; clock = release; }
            long long start = clock; long long service = [task[@"minutes"] longLongValue]; clock += service; totalService += service; sinceBreak += service; long long finish = clock; long long late = MAX(0, finish - [task[@"deadline"] longLongValue]); maxLate = MAX(maxLate, late); if (!jsonOutput) printf("%s\t%s\t%lld\t%lld\t%lld\n", [task[@"id"] UTF8String], [task[@"name"] UTF8String], start, finish, late); else [events addObject:@{ @"kind": @"errand", @"id": task[@"id"], @"name": task[@"name"], @"release": @(release), @"start": @(start), @"finish": @(finish), @"lateness": @(late) }]; firstStop = NO;
        }
        if (jsonOutput) { NSDictionary *result = @{ @"schema_version": @1, @"start": @(startOffset), @"events": events, @"total_service": @(totalService), @"total_break_time": @(totalBreak), @"total_idle_time": @(totalIdle), @"finish": @(clock), @"max_lateness": @(maxLate) }; NSError *jsonError = nil; NSData *output = [NSJSONSerialization dataWithJSONObject:result options:0 error:&jsonError]; if (!output || jsonError || fwrite(output.bytes, 1, output.length, stdout) != output.length || putchar('\n') == EOF) Fail(@"cannot write JSON output"); }
    }
    return 0;
}
