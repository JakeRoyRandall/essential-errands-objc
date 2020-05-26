#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

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
        NSString *inputPath = @"-"; BOOL hasInput = NO; long long startOffset = 0, breakAfter = 0, breakFor = 0; BOOL hasBreakAfter = NO, hasBreakFor = NO;
        for (int i = 1; i < argc; i++) { NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--start"] || [arg isEqualToString:@"--break-after"] || [arg isEqualToString:@"--break-for"]) {
                if (++i >= argc) Fail(@"option requires an integer value"); NSString *value = [NSString stringWithUTF8String:argv[i]]; NSScanner *scanner = [NSScanner scannerWithString:value]; long long number = 0;
                if (![scanner scanLongLong:&number] || !scanner.isAtEnd || number < 0 || number > 1000000 || ([arg isEqualToString:@"--break-after"] && number == 0) || ([arg isEqualToString:@"--break-for"] && number == 0)) Fail(@"option value is out of bounds");
                if ([arg isEqualToString:@"--start"]) startOffset = number; else if ([arg isEqualToString:@"--break-after"]) { breakAfter = number; hasBreakAfter = YES; } else { breakFor = number; hasBreakFor = YES; }
            } else if ([arg hasPrefix:@"-"] && ![arg isEqualToString:@"-"]) Fail(@"unknown option"); else if (hasInput) Fail(@"only one input file is allowed"); else { inputPath = arg; hasInput = YES; }
        }
        if (hasBreakAfter != hasBreakFor) Fail(@"--break-after and --break-for must be paired");
        NSData *data = ReadInput(inputPath); NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error || ![parsed isKindOfClass:[NSArray class]]) Fail(@"input must be a JSON array");
        NSArray *items = parsed; if (items.count > 100) Fail(@"at most 100 errands are supported");
        NSMutableSet *ids = [NSMutableSet set]; NSMutableArray *tasks = [NSMutableArray array]; NSUInteger order = 0;
        for (id raw in items) {
            if (![raw isKindOfClass:[NSDictionary class]]) Fail(@"each errand must be an object");
            NSString *taskID = raw[@"id"]; NSString *name = raw[@"name"]; long long minutes = 0, deadline = 0;
            if (![taskID isKindOfClass:[NSString class]] || taskID.length == 0 || taskID.length > 64 || [taskID rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || [ids containsObject:taskID]) Fail(@"ids must be unique strings up to 64 safe characters");
            if (![name isKindOfClass:[NSString class]] || name.length == 0 || name.length > 120 || [name rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound || !ValidInteger(raw[@"minutes"], &minutes) || !ValidInteger(raw[@"deadline"], &deadline)) Fail(@"name, minutes, and deadline have invalid types or bounds");
            [ids addObject:taskID]; [tasks addObject:@{ @"id": taskID, @"name": name, @"minutes": @(minutes), @"deadline": @(deadline), @"order": @(order++) }];
        }
        [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSComparisonResult result = [a[@"deadline"] compare:b[@"deadline"]]; return result == NSOrderedSame ? [a[@"order"] compare:b[@"order"]] : result; }];
        printf("id\tname\tstart\tfinish\tlateness\n"); long long clock = startOffset, sinceBreak = 0;
        for (NSUInteger i = 0; i < tasks.count; i++) { NSDictionary *task = tasks[i]; if (hasBreakAfter && i > 0 && sinceBreak >= breakAfter) { printf("BREAK\tbreak\t%lld\t%lld\t0\n", clock, clock + breakFor); clock += breakFor; sinceBreak = 0; } long long start = clock; clock += [task[@"minutes"] longLongValue]; sinceBreak += [task[@"minutes"] longLongValue]; long long finish = clock; long long late = MAX(0, finish - [task[@"deadline"] longLongValue]); printf("%s\t%s\t%lld\t%lld\t%lld\n", [task[@"id"] UTF8String], [task[@"name"] UTF8String], start, finish, late); }
    }
    return 0;
}
