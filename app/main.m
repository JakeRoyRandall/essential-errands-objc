#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static void Fail(NSString *message) { fprintf(stderr, "error: %s\n", message.UTF8String); exit(2); }
static BOOL ValidInteger(id value, long long *out) {
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    if (!isfinite(number) || floor(number) != number || number < 0 || number > 1000000) return NO;
    *out = [value longLongValue]; return YES;
}
static NSData *ReadInput(int argc, const char **argv) {
    FILE *input = stdin;
    if (argc == 2 && strcmp(argv[1], "-") != 0) {
        input = fopen(argv[1], "rb");
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
        if (argc > 2) Fail(@"usage: essential-errands [JSON_FILE|-]");
        NSData *data = ReadInput(argc, argv); NSError *error = nil;
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
        printf("id\tname\tstart\tfinish\tlateness\n"); long long clock = 0;
        for (NSDictionary *task in tasks) { long long start = clock; clock += [task[@"minutes"] longLongValue]; long long finish = clock; long long late = MAX(0, finish - [task[@"deadline"] longLongValue]); printf("%s\t%s\t%lld\t%lld\t%lld\n", [task[@"id"] UTF8String], [task[@"name"] UTF8String], start, finish, late); }
    }
    return 0;
}
