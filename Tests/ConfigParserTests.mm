#import "NMTest.h"
#import "ConfigParser.h"

static NSString *samplePolicies(void) {
    return @"config firewall policy\n"
            "    edit 1\n"
            "        set srcintf \"port1\"\n"
            "        set action accept\n"
            "    next\n"
            "    edit 2\n"
            "        set action deny\n"
            "    next\n"
            "end\n";
}

static void test_edit_entries_become_array(void) {
    NSDictionary *r = [[NMFortiGateConfigParser new] parseConfig:samplePolicies()];
    NSArray *policies = r[@"firewall_policy"];
    NM_EXPECT_TRUE([policies isKindOfClass:[NSArray class]]);
    NM_EXPECT_EQ_INT(policies.count, 2);
    NM_EXPECT_EQ_OBJ(policies[0][@"action"], @"accept");
    NM_EXPECT_EQ_OBJ(policies[1][@"action"], @"deny");
}

static void test_flat_section_and_unset(void) {
    NSString *cfg = @"config system global\n"
                     "    set hostname \"FW1\"\n"
                     "    set admintimeout 30\n"
                     "    unset admintimeout\n"
                     "end\n";
    NSDictionary *g = [[NMFortiGateConfigParser new] parseConfig:cfg][@"system_global"];
    NM_EXPECT_TRUE([g isKindOfClass:[NSDictionary class]]);
    NM_EXPECT_EQ_OBJ(g[@"hostname"], @"FW1");
    NM_EXPECT_NIL(g[@"admintimeout"]);   // removed by unset
}

static void test_id_round_trip(void) {
    NSString *cfg = @"config system interface\n"
                     "    edit \"port1\"\n"
                     "        set type physical\n"
                     "    next\n"
                     "    edit 007\n"
                     "        set type vlan\n"
                     "    next\n"
                     "end\n";
    NSArray *ifaces = [[NMFortiGateConfigParser new] parseConfig:cfg][@"system_interface"];
    // A name stays a string; "007" is not integer-round-trip-safe, so it stays a string too.
    NM_EXPECT_EQ_OBJ(ifaces[0][@"id"], @"port1");
    NM_EXPECT_EQ_OBJ(ifaces[1][@"id"], @"007");
}

static void test_missing_next_before_end(void) {
    NSString *cfg = @"config firewall address\n"
                     "    edit \"net1\"\n"
                     "        set subnet 192.168.1.0 255.255.255.0\n"
                     "end\n";   // note: no "next" before "end"
    NSArray *addrs = [[NMFortiGateConfigParser new] parseConfig:cfg][@"firewall_address"];
    NM_EXPECT_EQ_INT(addrs.count, 1);
    NM_EXPECT_EQ_OBJ(addrs[0][@"subnet"], @"192.168.1.0 255.255.255.0");
}

static void test_json_serialisable(void) {
    NSError *err = nil;
    NSData *json = NMConfigToJSONData([[NMFortiGateConfigParser new] parseConfig:samplePolicies()], &err);
    NM_EXPECT_NOTNIL(json);
    NM_EXPECT_NIL(err);
}

static void test_registry_auto_detect(void) {
    NM_EXPECT_NOTNIL([[NMConfigParserRegistry shared] parseConfig:samplePolicies()]);
    NM_EXPECT_NIL([[NMConfigParserRegistry shared]
                   parseConfig:@"this is just prose, not a config file"]);
}

void runConfigParserTests(void) {
    NM_RUN(test_edit_entries_become_array);
    NM_RUN(test_flat_section_and_unset);
    NM_RUN(test_id_round_trip);
    NM_RUN(test_missing_next_before_end);
    NM_RUN(test_json_serialisable);
    NM_RUN(test_registry_auto_detect);
}
