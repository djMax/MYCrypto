//
//  MYCertificateInfo.m
//  MYCrypto
//
//  Created by Jens Alfke on 6/2/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

// References:
// <http://tools.ietf.org/html/rfc3280> "RFC 3280: Internet X.509 Certificate Profile"
// <http://www.columbia.edu/~ariel/ssleay/layman.html> "Layman's Guide To ASN.1/BER/DER"
// <http://www.cs.auckland.ac.nz/~pgut001/pubs/x509guide.txt> "X.509 Style Guide"
// <http://en.wikipedia.org/wiki/X.509> Wikipedia article on X.509


#import "MYCertificateInfo.h"
#import "MYCrypto.h"
#import "MYASN1Object.h"
#import "MYOID.h"
#import "MYBERParser.h"
#import "MYDEREncoder.h"
#import "MYErrorUtils.h"


#define kDefaultExpirationTime (60.0 * 60.0 * 24.0 * 365.0)     /* that's 1 year */

/*  X.509 version number to generate. Even though my code doesn't (yet) add any of the post-v1
    metadata, it's necessary to write v3 or the resulting certs won't be accepted on some platforms,
    notably iPhone OS.
    "This field is used mainly for marketing purposes to claim that software is X.509v3 compliant 
    (even when it isn't)." --Peter Gutmann */
#define kCertRequestVersionNumber 3


/* "Safe" NSArray accessor -- returns nil if out of range. */
static id $atIf(NSArray *array, NSUInteger index) {
    return index < array.count ?[array objectAtIndex: index] :nil;
}


@interface MYCertificateName ()
- (id) _initWithComponents: (NSArray*)components;
@end

@interface MYCertificateInfo ()
@property (retain) NSArray *_root;
@end


#pragma mark -
@implementation MYCertificateInfo


static MYOID *kRSAAlgorithmID, *kRSAWithSHA1AlgorithmID, *kCommonNameOID,
             *kGivenNameOID, *kSurnameOID, *kDescriptionOID, *kEmailOID;


+ (void) initialize {
    if (!kEmailOID) {
        kRSAAlgorithmID = [[MYOID alloc] initWithComponents: (UInt32[]){1, 2, 840, 113549, 1, 1, 1,}
                                                      count: 7];
        kRSAWithSHA1AlgorithmID = [[MYOID alloc] initWithComponents: (UInt32[]){1, 2, 840, 113549, 1, 1, 5}
                                                              count: 7];
        kCommonNameOID = [[MYOID alloc] initWithComponents: (UInt32[]){2, 5, 4, 3}
                                                     count: 4];
        kGivenNameOID = [[MYOID alloc] initWithComponents: (UInt32[]){2, 5, 4, 42}
                                                    count: 4];
        kSurnameOID = [[MYOID alloc] initWithComponents: (UInt32[]){2, 5, 4, 4}
                                                  count: 4];
        kDescriptionOID = [[MYOID alloc] initWithComponents: (UInt32[]){2, 5, 4, 13}
                                                count: 4];
        kEmailOID = [[MYOID alloc] initWithComponents: (UInt32[]){1, 2, 840, 113549, 1, 9, 1}
                                                count: 7];
    }
}


- (id) initWithRoot: (NSArray*)root
{
    self = [super init];
    if (self != nil) {
        _root = [root retain];
    }
    return self;
}

+ (NSString*) validate: (id)root {
    NSArray *top = $castIf(NSArray,root);
    if (top.count < 3)
        return @"Too few top-level components";
    NSArray *info = $castIf(NSArray, [top objectAtIndex: 0]);
    if (info.count < 7)
        return @"Too few identity components";
    MYASN1Object *version = $castIf(MYASN1Object, [info objectAtIndex: 0]);
    if (!version || version.tag != 0)
        return @"Missing or invalid version";
    NSArray *versionComps = $castIf(NSArray, version.components);
    if (!versionComps || versionComps.count != 1)
        return @"Invalid version";
    NSNumber *versionNum = $castIf(NSNumber, [versionComps objectAtIndex: 0]);
    if (!versionNum || versionNum.intValue < 0 || versionNum.intValue > 2)
        return @"Unrecognized version number";
    return nil;
}


- (id) initWithCertificateData: (NSData*)data error: (NSError**)outError;
{
    if (outError) *outError = nil;
    id root = MYBERParse(data,outError);
    NSString *errorMsg = [[self class] validate: root];
    if (errorMsg) {
        if (outError && !*outError)
            *outError = MYError(2, MYASN1ErrorDomain, @"Invalid certificate: %@", errorMsg);
        [self release];
        return nil;
    }

    self = [self initWithRoot: root];
    if (self) {
        _data = [data copy];
    }
    return self;
}

- (void) dealloc
{
    [_root release];
    [_data release];
    [super dealloc];
}

- (BOOL) isEqual: (id)object {
    return [object isKindOfClass: [MYCertificateInfo class]]
        && [_root isEqual: ((MYCertificateInfo*)object)->_root];
}

- (NSArray*) _info       {return $castIf(NSArray,$atIf(_root,0));}

- (NSArray*) _validDates {return $castIf(NSArray, [self._info objectAtIndex: 4]);}

@synthesize _root;


- (NSDate*) validFrom       {return $castIf(NSDate, $atIf(self._validDates, 0));}
- (NSDate*) validTo         {return $castIf(NSDate, $atIf(self._validDates, 1));}

- (MYCertificateName*) subject {
    return [[[MYCertificateName alloc] _initWithComponents: [self._info objectAtIndex: 5]] autorelease];
}

- (MYCertificateName*) issuer {
    return [[[MYCertificateName alloc] _initWithComponents: [self._info objectAtIndex: 3]] autorelease];
}

- (BOOL) isSigned           {return [_root count] >= 3;}

- (BOOL) isRoot {
    id issuer = $atIf(self._info,3);
    return $equal(issuer, $atIf(self._info,5)) || $equal(issuer, $array());
}


- (NSData*) subjectPublicKeyData {
    NSArray *keyInfo = $cast(NSArray, $atIf(self._info, 6));
    MYOID *keyAlgorithmID = $castIf(MYOID, $atIf($castIf(NSArray,$atIf(keyInfo,0)), 0));
    if (!$equal(keyAlgorithmID, kRSAAlgorithmID))
        return nil;
    return $cast(MYBitString, $atIf(keyInfo, 1)).bits;
}

- (MYPublicKey*) subjectPublicKey {
    NSData *keyData = self.subjectPublicKeyData;
    if (!keyData) return nil;
    return [[[MYPublicKey alloc] initWithKeyData: keyData] autorelease];
}

- (NSData*) signedData {
    if (!_data)
        return nil;
    // The root object is a sequence; we want to extract the 1st object of that sequence.
    const UInt8 *certStart = _data.bytes;
    const UInt8 *start = MYBERGetContents(_data, nil);
    if (!start) return nil;
    size_t length = MYBERGetLength([NSData dataWithBytesNoCopy: (void*)start
                                                        length: _data.length - (start-certStart)
                                                  freeWhenDone: NO],
                                   NULL);
    if (length==0)
        return nil;
    return [NSData dataWithBytes: start length: (start + length - certStart)];
}

- (MYOID*) signatureAlgorithmID {
    return $castIf(MYOID, $atIf($castIf(NSArray,$atIf(_root,1)), 0));
}

- (NSData*) signature {
    id signature = $atIf(_root,2);
    if ([signature isKindOfClass: [MYBitString class]])
        signature = [signature bits];
    return $castIf(NSData,signature);
}

- (BOOL) verifySignatureWithKey: (MYPublicKey*)issuerPublicKey {
    if (!$equal(self.signatureAlgorithmID, kRSAWithSHA1AlgorithmID))
        return NO;
    NSData *signedData = self.signedData;
    NSData *signature = self.signature;
    return signedData && signature && [issuerPublicKey verifySignature: signature ofData: signedData];
}


@end




#pragma mark -
@implementation MYCertificateRequest

- (id) initWithPublicKey: (MYPublicKey*)publicKey {
    Assert(publicKey);
    id empty = [NSNull null];
    id version = [[MYASN1Object alloc] initWithTag: 0 
                                           ofClass: 2
                                        components: $array($object(kCertRequestVersionNumber - 1))];
    NSArray *root = $array( $marray(version,
                                    empty,       // serial #
                                    $array(kRSAAlgorithmID),
                                    $marray(),
                                    $marray(empty, empty),
                                    $marray(),
                                    $array( $array(kRSAAlgorithmID, empty),
                                           [MYBitString bitStringWithData: publicKey.keyData] ) ) );
    self = [super initWithRoot: root];
    [version release];
    if (self) {
        _publicKey = publicKey.retain;
    }
    return self;
}
    
- (void) dealloc
{
    [_publicKey release];
    [super dealloc];
}


- (NSDate*) validFrom       {return [super validFrom];}
- (NSDate*) validTo         {return [super validTo];}

- (void) setValidFrom: (NSDate*)validFrom {
    [(NSMutableArray*)self._validDates replaceObjectAtIndex: 0 withObject: validFrom];
}

- (void) setValidTo: (NSDate*)validTo {
    [(NSMutableArray*)self._validDates replaceObjectAtIndex: 1 withObject: validTo];
}


- (void) fillInValues {
    NSMutableArray *info = (NSMutableArray*)self._info;
    // Set serial number if there isn't one yet:
    if (!$castIf(NSNumber, [info objectAtIndex: 1])) {
        UInt64 serial = floor(CFAbsoluteTimeGetCurrent() * 1000);
        [info replaceObjectAtIndex: 1 withObject: $object(serial)];
    }
    
    // Set up valid date range if there isn't one yet:
    NSDate *validFrom = self.validFrom;
    if (!validFrom)
        validFrom = self.validFrom = [NSDate date];
    NSDate *validTo = self.validTo;
    if (!validTo)
        self.validTo = [validFrom dateByAddingTimeInterval: kDefaultExpirationTime]; 
}


- (NSData*) requestData: (NSError**)outError {
    [self fillInValues];
    return [MYDEREncoder encodeRootObject: self._info error: outError];
}


- (NSData*) selfSignWithPrivateKey: (MYPrivateKey*)privateKey 
                             error: (NSError**)outError 
{
    AssertEqual(privateKey.publicKey, _publicKey);  // Keys must form a pair
    
    // Copy subject to issuer:
    NSMutableArray *info = (NSMutableArray*)self._info;
    [info replaceObjectAtIndex: 3 withObject: [info objectAtIndex: 5]];
    
    // Sign the request:
    NSData *dataToSign = [self requestData: outError];
    if (!dataToSign)
        return nil;
    MYBitString *signature = [MYBitString bitStringWithData: [privateKey signData: dataToSign]];
    
    // Generate and encode the certificate:
    NSArray *root = $array(info, 
                           $array(kRSAWithSHA1AlgorithmID, [NSNull null]),
                           signature);
    return [MYDEREncoder encodeRootObject: root error: outError];
}


- (MYIdentity*) createSelfSignedIdentityWithPrivateKey: (MYPrivateKey*)privateKey
                                                 error: (NSError**)outError
{
    Assert(privateKey.keychain!=nil);
    NSData *certData = [self selfSignWithPrivateKey: privateKey error: outError];
    if (!certData)
        return nil;
    MYCertificate *cert = [privateKey.keychain importCertificate: certData];
    Assert(cert!=nil);
    Assert(cert.keychain!=nil);
    AssertEqual(cert.publicKey.keyData, _publicKey.keyData);
    MYIdentity *identity = cert.identity;
    Assert(identity!=nil);
    return identity;
}


@end



#pragma mark -
@implementation MYCertificateName

- (id) _initWithComponents: (NSArray*)components
{
    self = [super init];
    if (self != nil) {
        _components = [components retain];
    }
    return self;
}

- (void) dealloc
{
    [_components release];
    [super dealloc];
}

- (BOOL) isEqual: (id)object {
    return [object isKindOfClass: [MYCertificateName class]]
        && [_components isEqual: ((MYCertificateName*)object)->_components];
}

- (NSArray*) _pairForOID: (MYOID*)oid {
    for (id nameEntry in _components) {
        for (id pair in $castIf(NSSet,nameEntry)) {
            if ([pair isKindOfClass: [NSArray class]] && [pair count] == 2) {
                if ($equal(oid, [pair objectAtIndex: 0]))
                    return pair;
            }
        }
    }
    return nil;
}

- (NSString*) stringForOID: (MYOID*)oid {
    return [[self _pairForOID: oid] objectAtIndex: 1];
}

- (void) setString: (NSString*)value forOID: (MYOID*)oid {
    NSMutableArray *pair = (NSMutableArray*) [self _pairForOID: oid];
    if (pair) {
        if (value)
            [pair replaceObjectAtIndex: 1 withObject: value];
        else
            Assert(NO,@"-setString:forOID: removing strings is unimplemented");//FIX
    } else {
        if (value)
            [(NSMutableArray*)_components addObject: [NSSet setWithObject: $marray(oid,value)]];
    }
}

- (NSString*) commonName    {return [self stringForOID: kCommonNameOID];}
- (NSString*) givenName     {return [self stringForOID: kGivenNameOID];}
- (NSString*) surname       {return [self stringForOID: kSurnameOID];}
- (NSString*) nameDescription {return [self stringForOID: kDescriptionOID];}
- (NSString*) emailAddress  {return [self stringForOID: kEmailOID];}

- (void) setCommonName: (NSString*)commonName   {[self setString: commonName forOID: kCommonNameOID];}
- (void) setGivenName: (NSString*)givenName     {[self setString: givenName forOID: kGivenNameOID];}
- (void) setSurname: (NSString*)surname         {[self setString: surname forOID: kSurnameOID];}
- (void) setNameDescription: (NSString*)desc    {[self setString: desc forOID: kDescriptionOID];}
- (void) setEmailAddress: (NSString*)email      {[self setString: email forOID: kEmailOID];}


@end


/*
 Copyright (c) 2009, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
