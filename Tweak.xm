#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>
#import <objc/runtime.h>
#import <substrate.h>

static const NSInteger kAlignedMajorVersion = 26;
static const NSInteger kWatchOSToIOSOffset = 7;

static const long long kMaxPairingVersion = 999;
static const long long kMinPairingVersion = 1;

static NSString *const kNanoRegistryDomain = @"com.apple.NanoRegistry";
static NSString *const kPairedSyncDomain = @"com.apple.pairedsync";

#pragma mark - Preference method

static BOOL WritePreference(NSString *domain, NSString *key, id value) {
	CFStringRef cfDomain = (__bridge CFStringRef)domain;
	CFStringRef cfKey = (__bridge CFStringRef)key;

	CFPropertyListRef current = CFPreferencesCopyValue(cfKey, cfDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
	BOOL unchanged = current && CFEqual(current, (__bridge CFTypeRef)value);
	if (current) CFRelease(current);
	if (unchanged) return NO;

	CFPreferencesSetValue(cfKey, (__bridge CFPropertyListRef)value, cfDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
	return YES;
}

static void FlushPreferenceCache(NSString *domain) {
	static void (*flush)(CFStringRef, CFStringRef);
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		flush = (void (*)(CFStringRef, CFStringRef))dlsym(RTLD_DEFAULT, "_CFPreferencesFlushCachesForIdentifier");
	});
	if (flush) flush((__bridge CFStringRef)domain, CFSTR("mobile"));
}

static void ApplyPairingPreferences(void) {
	if (geteuid() != 501) return;

	BOOL changed = NO;
	changed |= WritePreference(kNanoRegistryDomain, @"minPairingCompatibilityVersion", @(kMinPairingVersion));
	changed |= WritePreference(kNanoRegistryDomain, @"maxPairingCompatibilityVersion", @(kMaxPairingVersion));
	changed |= WritePreference(kNanoRegistryDomain, @"minPairingCompatibilityVersionWithChipID", @(kMinPairingVersion));
	changed |= WritePreference(kNanoRegistryDomain, @"minQuickSwitchCompatibilityVersion", @(kMinPairingVersion));
	changed |= WritePreference(kNanoRegistryDomain, @"IOS_PAIRING_EOL_MIN_PAIRING_COMPATIBILITY_VERSION_CHIPIDS", @"");

	if (changed) {
		CFPreferencesSynchronize((__bridge CFStringRef)kNanoRegistryDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
		FlushPreferenceCache(kNanoRegistryDomain);
	}

	if (WritePreference(kPairedSyncDomain, @"activityTimeout", @30)) {
		CFPreferencesSynchronize((__bridge CFStringRef)kPairedSyncDomain, CFSTR("mobile"), kCFPreferencesAnyHost);
		FlushPreferenceCache(kPairedSyncDomain);
	}
}

#pragma mark - Runtime method

@interface NRPairingCompatibilityVersionInfo : NSObject
@end

@interface NRDevice : NSObject
- (id)valueForProperty:(id)property;
@end

@interface NRMutableDevice : NRDevice
@end

@interface ACXRemoteApplication : NSObject
@end

static NSString *NanoRegistryPropertyKey(const char *symbol) {
	void *address = dlsym(RTLD_DEFAULT, symbol);
	return address ? *(NSString *__unsafe_unretained *)address : nil;
}

//pair photo stuff
static BOOL DeviceRunsNewerOSThanHost(NRDevice *device) {
	static NSString *marketingKey, *systemKey;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		marketingKey = NanoRegistryPropertyKey("NRDevicePropertyMarketingVersion");
		systemKey = NanoRegistryPropertyKey("NRDevicePropertySystemVersion");
	});

	id version = marketingKey ? [device valueForProperty:marketingKey] : nil;
	if (![version isKindOfClass:NSString.class] && systemKey) {
		version = [device valueForProperty:systemKey];
	}
	if (![version isKindOfClass:NSString.class]) return NO;

	NSInteger major = [(NSString *)version integerValue];
	if (major <= 0) return NO;
	if (major < kAlignedMajorVersion) major += kWatchOSToIOSOffset;

	return major > NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
}

%group DeviceCapabilities
%hook NRDevice
- (BOOL)supportsCapability:(id)capability {
	return %orig ?: DeviceRunsNewerOSThanHost(self);
}
%end

%hook NRMutableDevice
- (BOOL)supportsCapability:(id)capability {
	return %orig ?: DeviceRunsNewerOSThanHost(self);
}
%end
%end

%group AppInstall
%hook ACXRemoteApplication
//sync
- (BOOL)isRuntimeCompatibleWithOSVersion:(id)version {
	return YES;
}
%end
%end

%group PairingGate
%hook NRPairingCompatibilityVersionInfo
//fix pair ig
- (long long)maxPairingCompatibilityVersion {
	return kMaxPairingVersion;
}

- (long long)minPairingCompatibilityVersion {
	return kMinPairingVersion;
}

- (long long)minPairingCompatibilityVersionWithChipID {
	return kMinPairingVersion;
}

- (long long)minQuickSwitchCompatibilityVersion {
	return kMinPairingVersion;
}

- (long long)minPairingCompatibilityVersionForChipID:(id)chipID {
	return kMinPairingVersion;
}

- (long long)minPairingCompatibilityVersionForChipID:(id)chipID name:(id)name defaultVersion:(long long)version {
	return kMinPairingVersion;
}

- (long long)minQuickSwitchPairingCompatibilityVersionForChipID:(id)chipID {
	return kMinPairingVersion;
}

- (long long)minPairingCompatibilityVersionForWatchProductType:(id)productType {
	return kMinPairingVersion;
}

- (long long)maxPairingCompatibilityVersionForPhoneProductType:(id)productType {
	return kMaxPairingVersion;
}

- (unsigned long long)pairingCompatibilitySupportStateForAdvertisingWatchVersion:(long long)version {
	return 1;
}
%end
%end

#pragma mark - Message auto-uninstall fix (ported from WatchFix AppsSupport)

@interface ACXAvailableApplicationManager : NSObject
@end

@interface MIEmbeddedWatchBundle : NSObject
- (BOOL)isApplicableToOSVersion:(id)version error:(id *)error;
@end

static BOOL watchFixIsEqualCString(const char *s1, const char *s2) {
	if (!s1 || !s2) return NO;
	return strcmp(s1, s2) == 0;
}

%group MessageMappingFix

%hook ACXAvailableApplicationManager

- (NSDictionary *)_supplementalSystemAppBundleIDMappingForWatchOSSixAndLater {
	NSDictionary *result = %orig;
	NSMutableDictionary *mapping = [result mutableCopy] ?: [NSMutableDictionary dictionary];
	NSString *sms = @"com.apple.MobileSMS";
	[mapping setObject:sms forKey:sms];
	return mapping;
}

%end

%end

%group WatchBundleFix

%hook MIEmbeddedWatchBundle

- (BOOL)isApplicableToKnownWatchOSVersion {
	return [self isApplicableToOSVersion:@"11.9999" error:nil];
}

- (NSString *)currentOSVersionForValidationWithError:(id *)error {
	return @"11.9999";
}

%end

%end

static void InitMessageUninstallFixHooks(void) {
	Class managerClass = objc_lookUpClass("ACXAvailableApplicationManager");
	if (managerClass) {
		%init(MessageMappingFix, ACXAvailableApplicationManager=managerClass);
	}
	Class watchBundleClass = objc_lookUpClass("MIEmbeddedWatchBundle");
	if (watchBundleClass) {
		%init(WatchBundleFix, MIEmbeddedWatchBundle=watchBundleClass);
	}
}

#pragma mark - APS keep-alive (ported from WatchFix APSSupport)

@interface APSIDSProxyManager : NSObject
- (void)sendProxyIsConnected:(BOOL)isConnected guid:(NSString *)guid environmentName:(NSString *)environmentName;
@end

@interface APSEnvironment : NSObject
- (NSString *)name;
@end

@interface APSProxyClient : NSObject
- (BOOL)isActive;
- (APSIDSProxyManager *)proxyManager;
- (void)incomingPresenceWithCertificate:(NSData *)certificate
								  nonce:(NSData *)nonce
								signature:(NSData *)signature
								  token:(NSData *)token
							  hwVersion:(NSString *)hwVersion
							  swVersion:(NSString *)swVersion
								swBuild:(NSString *)swBuild;
@end

static id WatchFixCopyObjectIvarValueByName(id object, const char *name, Class expectedClass) {
	if (!object || !name) {
		return nil;
	}
	Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
	if (!ivar) {
		return nil;
	}
	id value = object_getIvar(object, ivar);
	if (!value || (expectedClass && ![value isKindOfClass:expectedClass])) {
		return nil;
	}
	return value;
}

static const char *WatchFixSkipObjCTypeQualifiers(const char *type) {
	if (!type) {
		return NULL;
	}
	while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
		   *type == 'O' || *type == 'R' || *type == 'V') {
		type++;
	}
	return type;
}

static BOOL WatchFixIsIntegerArgumentType(const char *type) {
	type = WatchFixSkipObjCTypeQualifiers(type);
	if (!type || !*type) {
		return NO;
	}
	switch (*type) {
		case 'c': case 'C':
		case 's': case 'S':
		case 'i': case 'I':
		case 'l': case 'L':
		case 'q': case 'Q':
		case 'B':
			return YES;
		default:
			return NO;
	}
}

static char *WatchFixCopyThirdArgumentType(id object, SEL selector) {
	if (!object || !selector) {
		return NULL;
	}
	Method method = class_getInstanceMethod(object_getClass(object), selector);
	if (!method) {
		return NULL;
	}
	unsigned int argumentCount = method_getNumberOfArguments(method);
	if (argumentCount <= 2) {
		return NULL;
	}
	return method_copyArgumentType(method, 2);
}

static BOOL WatchFixCallBoolMethodWithIntegerArgument(id object, SEL selector, NSInteger value, BOOL *result) {
	if (!object || !selector || !result || ![object respondsToSelector:selector]) {
		return NO;
	}
	char *argumentType = WatchFixCopyThirdArgumentType(object, selector);
	BOOL isInteger = WatchFixIsIntegerArgumentType(argumentType);
	if (!isInteger) {
		if (argumentType) {
			free(argumentType);
		}
		return NO;
	}
	free(argumentType);

	IMP implementation = [object methodForSelector:selector];
	if (!implementation) {
		return NO;
	}
	typedef BOOL (*WFBoolIntegerIMP)(id, SEL, NSInteger);
	*result = ((WFBoolIntegerIMP)implementation)(object, selector, value);
	return YES;
}

static BOOL WatchFixShouldReportProxyConnectedState(APSProxyClient *client) {
	if (!client || ![client respondsToSelector:@selector(isActive)]) {
		return NO;
	}
	if (![client isActive]) {
		return NO;
	}

	SEL connectedSelector = NSSelectorFromString(@"isConnectedOnInterface:");
	SEL disconnectSelector = NSSelectorFromString(@"needsToDisconnectOnInterface:");

	char *connectedType = WatchFixCopyThirdArgumentType(client, connectedSelector);
	char *disconnectType = WatchFixCopyThirdArgumentType(client, disconnectSelector);
	BOOL legacyIntegerABI = WatchFixIsIntegerArgumentType(connectedType) && WatchFixIsIntegerArgumentType(disconnectType);

	if (connectedType) free(connectedType);
	if (disconnectType) free(disconnectType);

	if (!legacyIntegerABI) {
		// Incoming presence itself is the strong signal that a live proxy peer
		// just contacted apsd. Keep the active-client guard but do not guess
		// what object Apple now expects as the interface key.
		return YES;
	}

	for (NSInteger interface = 0; interface <= 1; interface++) {
		BOOL connected = NO;
		BOOL needsDisconnect = NO;

		if (!WatchFixCallBoolMethodWithIntegerArgument(client, connectedSelector, interface, &connected) ||
			!WatchFixCallBoolMethodWithIntegerArgument(client, disconnectSelector, interface, &needsDisconnect)) {
			return YES;
		}

		if (connected && !needsDisconnect) {
			return YES;
		}
	}

	return NO;
}

%group APSKeepAlive

%hook APSProxyClient

- (void)incomingPresenceWithCertificate:(NSData *)certificate
								  nonce:(NSData *)nonce
								signature:(NSData *)signature
								  token:(NSData *)token
							  hwVersion:(NSString *)hwVersion
							  swVersion:(NSString *)swVersion
								swBuild:(NSString *)swBuild {
	%orig;

	if (!WatchFixShouldReportProxyConnectedState(self)) {
		return;
	}

	NSString *guid = WatchFixCopyObjectIvarValueByName(self, "_guid", [NSString class]);
	APSEnvironment *environment = WatchFixCopyObjectIvarValueByName(self, "_environment", NSClassFromString(@"APSEnvironment"));
	NSString *environmentName = [environment name];
	APSIDSProxyManager *proxyManager = [self proxyManager];

	if (guid.length == 0 || environmentName.length == 0 || !proxyManager) {
		return;
	}

	[proxyManager sendProxyIsConnected:YES guid:guid environmentName:environmentName];
}

%end

%end

static void InitAPSKeepAliveHooks(void) {
	Class proxyClientClass = objc_lookUpClass("APSProxyClient");
	if (proxyClientClass) {
		%init(APSKeepAlive, APSProxyClient=proxyClientClass);
	}
}

#pragma mark - BLE NearbyAction 0x00 block (ported from WatchFix BLEPairingFix)

%group BLENearbyActionFix

%hook CBDevice

- (void)setNearbyActionV2Type:(uint8_t)type {
	if (type == 0x00) {
		return;
	}
	%orig;
}

%end

%end

static void InitBLENearbyActionFixHooks(void) {
	Class cbDeviceClass = objc_lookUpClass("CBDevice");
	if (cbDeviceClass) {
		%init(BLENearbyActionFix, CBDevice=cbDeviceClass);
	}
}

%ctor {
	@autoreleasepool {
		if (NSClassFromString(@"NRPairingCompatibilityVersionInfo")) {
			%init(PairingGate);
		}
		if (NSClassFromString(@"NRDevice")) {
			%init(DeviceCapabilities);
		}
		if (NSClassFromString(@"ACXRemoteApplication")) {
			%init(AppInstall);
		}
		ApplyPairingPreferences();

		const char *progname = getprogname();
		if (watchFixIsEqualCString(progname, "apsd")) {
			InitAPSKeepAliveHooks();
		} else if (watchFixIsEqualCString(progname, "appconduitd") ||
				   watchFixIsEqualCString(progname, "installd") ||
				   watchFixIsEqualCString(progname, "MobileInstallationHelperService")) {
			InitMessageUninstallFixHooks();
		} else if (watchFixIsEqualCString(progname, "bluetoothd")) {
			InitBLENearbyActionFixHooks();
		}
	}
}
