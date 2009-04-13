//
//  MYCertificate.h
//  MYCrypto
//
//  Created by Jens Alfke on 3/26/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYKeychainItem.h"

#if !TARGET_OS_IPHONE
#import <Security/cssmtype.h>
#endif

@class MYPublicKey;


/** An X.509 certificate. */
@interface MYCertificate : MYKeychainItem {
    @private
    SecCertificateRef _certificateRef;
}

/** Creates a MYCertificate object for an existing Keychain certificate reference. */
+ (MYCertificate*) certificateWithCertificateRef: (SecCertificateRef)certificateRef;

/** Initializes a MYCertificate object for an existing Keychain certificate reference. */
- (id) initWithCertificateRef: (SecCertificateRef)certificateRef;

/** Creates a MYCertificate object from exported key data, but does not add it to any keychain. */
- (id) initWithCertificateData: (NSData*)data;

/** Checks whether two MYCertificate objects have bit-for-bit identical certificate data. */
- (BOOL)isEqualToCertificate:(MYCertificate*)cert;

/** The Keychain object reference for this certificate. */
@property (readonly) SecCertificateRef certificateRef;

/** The certificate's data. */
@property (readonly) NSData *certificateData;

/** The certificate's public key. */
@property (readonly) MYPublicKey *publicKey;

/** The name of the subject (owner) of the certificate. */
@property (readonly) NSString *commonName;


/** @name Mac-Only
 *  Functionality not available on iPhone. 
 */
//@{
#if !TARGET_OS_IPHONE

/** Creates a MYCertificate object from exported key data, but does not add it to any keychain. */
- (id) initWithCertificateData: (NSData*)data
                          type: (CSSM_CERT_TYPE) type
                      encoding: (CSSM_CERT_ENCODING) encoding;

/** The list (if any) of the subject's email addresses. */
@property (readonly) NSArray *emailAddresses;

/** Finds the current 'preferred' certificate for the given name string. */
+ (MYCertificate*) preferredCertificateForName: (NSString*)name;

/** Associates the receiver as the preferred certificate for the given name string. */
- (BOOL) setPreferredCertificateForName: (NSString*)name;

#endif
//@}


/** @name Expert
 */
//@{
#if !TARGET_OS_IPHONE

+ (SecPolicyRef) X509Policy;
+ (SecPolicyRef) SSLPolicy;
+ (SecPolicyRef) SMIMEPolicy;
- (CSSM_CERT_TYPE) certificateType;
- (NSArray*) trustSettings;
- (BOOL) setUserTrust: (SecTrustUserSetting)trustSetting;
    
#endif
//@}
    
@end


NSString* MYPolicyGetName( SecPolicyRef policy );
NSString* MYTrustDescribe( SecTrustRef trust );
NSString* MYTrustResultDescribe( SecTrustResultType result );
