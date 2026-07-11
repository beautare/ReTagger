#import "TagLibBridge.h"

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <taglib/tag_c.h>
#undef BOOL
#import <stdlib.h>

NSString * const TagLibBridgeErrorDomain = @"vip.retagger.taglib";

static NSRecursiveLock *gTagLibLock = nil;
__attribute__((constructor)) static void InitializeTagLibLock(void) {
    gTagLibLock = [[NSRecursiveLock alloc] init];
}

// MARK: - TagLibBridgeMetadataResult Implementation

@implementation TagLibBridgeMetadataResult
@end

// MARK: - Function Pointer Types

typedef TagLib_File *(*TagLibFileNewFn)(const char *);
typedef void (*TagLibFileFreeFn)(TagLib_File *);
typedef BOOL (*TagLibFileIsValidFn)(const TagLib_File *);
typedef TagLib_Tag *(*TagLibFileTagFn)(const TagLib_File *);
typedef BOOL (*TagLibFileSaveFn)(TagLib_File *);
typedef void (*TagLibSetStringsUnicodeFn)(BOOL);
typedef void (*TagLibSetDefaultEncodingFn)(TagLib_ID3v2_Encoding);

// Write functions
typedef void (*TagLibTagSetStringFn)(TagLib_Tag *, const char *);
typedef void (*TagLibTagSetYearFn)(TagLib_Tag *, unsigned int);

// Read functions
typedef char *(*TagLibTagGetStringFn)(const TagLib_Tag *);
typedef unsigned int (*TagLibTagGetYearFn)(const TagLib_Tag *);
typedef void (*TagLibTagFreeStringsFn)(char *);

// Audio properties
typedef const TagLib_AudioProperties *(*TagLibFileAudioPropertiesFn)(const TagLib_File *);
typedef int (*TagLibAPGetIntFn)(const TagLib_AudioProperties *);

typedef struct {
    // Core functions
    TagLibFileNewFn fileNew;
    TagLibFileFreeFn fileFree;
    TagLibFileIsValidFn fileIsValid;
    TagLibFileTagFn fileTag;
    TagLibFileSaveFn fileSave;
    TagLibSetStringsUnicodeFn setStringsUnicode;
    TagLibSetDefaultEncodingFn setDefaultEncoding;
    
    // Write functions
    TagLibTagSetStringFn setTitle;
    TagLibTagSetStringFn setArtist;
    TagLibTagSetStringFn setAlbum;
    TagLibTagSetStringFn setGenre;
    TagLibTagSetYearFn setYear;
    
    // Read functions
    TagLibTagGetStringFn getTitle;
    TagLibTagGetStringFn getArtist;
    TagLibTagGetStringFn getAlbum;
    TagLibTagGetStringFn getGenre;
    TagLibTagGetYearFn getYear;
    TagLibTagFreeStringsFn freeStrings;
    
    // Audio properties functions
    TagLibFileAudioPropertiesFn fileAudioProperties;
    TagLibAPGetIntFn apGetLength;
    TagLibAPGetIntFn apGetBitrate;
    TagLibAPGetIntFn apGetSampleRate;
    TagLibAPGetIntFn apGetChannels;
} TagLibSymbols;

static TagLibSymbols gSymbols;
static void *gTagLibHandle = NULL;
static dispatch_once_t gTagLibLoadOnce;
static NSError *gTagLibLoadError = nil;

static NSString *FrameworkTagLibPath(NSString *name) {
    NSURL *frameworksURL = [NSBundle mainBundle].privateFrameworksURL;
    if (!frameworksURL) {
        frameworksURL = [[[NSBundle mainBundle] bundleURL] URLByAppendingPathComponent:@"Contents/Frameworks" isDirectory:YES];
    }
    NSURL *libraryURL = [frameworksURL URLByAppendingPathComponent:name];
    return libraryURL.path;
}

static BOOL LoadTagLib(NSError **error) {
    dispatch_once(&gTagLibLoadOnce, ^{
        NSString *libraryPath = FrameworkTagLibPath(@"libtag_c.2.1.1.dylib");
        gTagLibHandle = dlopen(libraryPath.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (!gTagLibHandle) {
            const char *message = dlerror();
            NSString *detail = message ? [NSString stringWithUTF8String:message] : @"无法加载 libtag_c";
            gTagLibLoadError = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                                  code:TagLibBridgeErrorCodeOpenFile
                                              userInfo:@{NSLocalizedDescriptionKey: detail}];
            return;
        }

        // Core functions
        gSymbols.fileNew = (TagLibFileNewFn)dlsym(gTagLibHandle, "taglib_file_new");
        gSymbols.fileFree = (TagLibFileFreeFn)dlsym(gTagLibHandle, "taglib_file_free");
        gSymbols.fileIsValid = (TagLibFileIsValidFn)dlsym(gTagLibHandle, "taglib_file_is_valid");
        gSymbols.fileTag = (TagLibFileTagFn)dlsym(gTagLibHandle, "taglib_file_tag");
        gSymbols.fileSave = (TagLibFileSaveFn)dlsym(gTagLibHandle, "taglib_file_save");
        gSymbols.setStringsUnicode = (TagLibSetStringsUnicodeFn)dlsym(gTagLibHandle, "taglib_set_strings_unicode");
        gSymbols.setDefaultEncoding = (TagLibSetDefaultEncodingFn)dlsym(gTagLibHandle, "taglib_id3v2_set_default_text_encoding");
        
        // Write functions
        gSymbols.setTitle = (TagLibTagSetStringFn)dlsym(gTagLibHandle, "taglib_tag_set_title");
        gSymbols.setArtist = (TagLibTagSetStringFn)dlsym(gTagLibHandle, "taglib_tag_set_artist");
        gSymbols.setAlbum = (TagLibTagSetStringFn)dlsym(gTagLibHandle, "taglib_tag_set_album");
        gSymbols.setGenre = (TagLibTagSetStringFn)dlsym(gTagLibHandle, "taglib_tag_set_genre");
        gSymbols.setYear = (TagLibTagSetYearFn)dlsym(gTagLibHandle, "taglib_tag_set_year");
        
        // Read functions
        gSymbols.getTitle = (TagLibTagGetStringFn)dlsym(gTagLibHandle, "taglib_tag_title");
        gSymbols.getArtist = (TagLibTagGetStringFn)dlsym(gTagLibHandle, "taglib_tag_artist");
        gSymbols.getAlbum = (TagLibTagGetStringFn)dlsym(gTagLibHandle, "taglib_tag_album");
        gSymbols.getGenre = (TagLibTagGetStringFn)dlsym(gTagLibHandle, "taglib_tag_genre");
        gSymbols.getYear = (TagLibTagGetYearFn)dlsym(gTagLibHandle, "taglib_tag_year");
        gSymbols.freeStrings = (TagLibTagFreeStringsFn)dlsym(gTagLibHandle, "taglib_tag_free_strings");
        
        // Audio properties functions
        gSymbols.fileAudioProperties = (TagLibFileAudioPropertiesFn)dlsym(gTagLibHandle, "taglib_file_audioproperties");
        gSymbols.apGetLength = (TagLibAPGetIntFn)dlsym(gTagLibHandle, "taglib_audioproperties_length");
        gSymbols.apGetBitrate = (TagLibAPGetIntFn)dlsym(gTagLibHandle, "taglib_audioproperties_bitrate");
        gSymbols.apGetSampleRate = (TagLibAPGetIntFn)dlsym(gTagLibHandle, "taglib_audioproperties_samplerate");
        gSymbols.apGetChannels = (TagLibAPGetIntFn)dlsym(gTagLibHandle, "taglib_audioproperties_channels");

        // Validate required symbols
        if (!gSymbols.fileNew || !gSymbols.fileFree || !gSymbols.fileIsValid ||
            !gSymbols.fileTag || !gSymbols.fileSave || !gSymbols.setStringsUnicode ||
            !gSymbols.setTitle || !gSymbols.setArtist || !gSymbols.setAlbum ||
            !gSymbols.setGenre || !gSymbols.setYear ||
            !gSymbols.getTitle || !gSymbols.getArtist || !gSymbols.getAlbum ||
            !gSymbols.getGenre || !gSymbols.getYear) {
            gTagLibLoadError = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                                  code:TagLibBridgeErrorCodeOpenFile
                                              userInfo:@{NSLocalizedDescriptionKey: @"TagLib C API 符号缺失"}];
            dlclose(gTagLibHandle);
            gTagLibHandle = NULL;
            return;
        }

        gSymbols.setStringsUnicode(YES);
        if (gSymbols.setDefaultEncoding) {
            gSymbols.setDefaultEncoding(TagLib_ID3v2_UTF8);
        }
    });

    if (!gTagLibHandle) {
        if (error) {
            *error = gTagLibLoadError;
        }
        return NO;
    }
    return YES;
}

// MARK: - Helper Functions

static unsigned int ParseUnsignedInteger(NSString *value) {
    if (value.length == 0) {
        return 0;
    }
    NSString *trimmed = [[value componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSArray<NSString *> *components = [trimmed componentsSeparatedByString:@"/"];
    NSString *target = components.firstObject ?: trimmed;
    const char *cString = target.UTF8String;
    if (!cString) {
        return 0;
    }
    char *endPointer = NULL;
    unsigned long parsed = strtoul(cString, &endPointer, 10);
    if (endPointer == cString) {
        return 0;
    }
    if (parsed > UINT_MAX) {
        return UINT_MAX;
    }
    return (unsigned int)parsed;
}

static void SetTagString(TagLibTagSetStringFn setter, TagLib_Tag *tag, NSString * _Nullable value) {
    const char *utf8 = value.length > 0 ? value.UTF8String : "";
    setter(tag, utf8);
}

static NSString * _Nullable GetTagString(TagLibTagGetStringFn getter, const TagLib_Tag *tag) {
    char *value = getter(tag);
    if (!value) {
        return nil;
    }
    NSString *result = [NSString stringWithUTF8String:value];
    // Note: TagLib C API uses taglib_tag_free_strings to free the strings,
    // but in practice the strings are managed by the tag object and freed when the file is freed.
    // We'll call freeStrings if available for safety.
    if (gSymbols.freeStrings) {
        gSymbols.freeStrings(value);
    }
    // Return nil for empty strings
    if (result.length == 0) {
        return nil;
    }
    return result;
}

// MARK: - Read Metadata Implementation

TagLibBridgeMetadataResult * _Nullable TagLibBridgeReadMetadata(NSString *path,
                                                                 NSError * _Nullable * _Nullable error) {
    [gTagLibLock lock];
    @autoreleasepool {
        if (path.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeInvalidInput
                                         userInfo:@{NSLocalizedDescriptionKey: @"无效的文件路径"}];
            }
            [gTagLibLock unlock];
            return nil;
        }

        if (!LoadTagLib(error)) {
            [gTagLibLock unlock];
            return nil;
        }

        TagLib_File *file = gSymbols.fileNew(path.fileSystemRepresentation);
        if (!file) {
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeOpenFile
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法打开音频文件"}];
            }
            [gTagLibLock unlock];
            return nil;
        }

        if (!gSymbols.fileIsValid(file)) {
            gSymbols.fileFree(file);
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeOpenFile
                                         userInfo:@{NSLocalizedDescriptionKey: @"音频文件无效或已损坏"}];
            }
            [gTagLibLock unlock];
            return nil;
        }

        TagLib_Tag *tag = gSymbols.fileTag(file);
        if (!tag) {
            gSymbols.fileFree(file);
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeRead
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法获取标签信息"}];
            }
            [gTagLibLock unlock];
            return nil;
        }

        TagLibBridgeMetadataResult *result = [[TagLibBridgeMetadataResult alloc] init];
        
        // Read tag strings
        result.title = GetTagString(gSymbols.getTitle, tag);
        result.artist = GetTagString(gSymbols.getArtist, tag);
        result.album = GetTagString(gSymbols.getAlbum, tag);
        result.genre = GetTagString(gSymbols.getGenre, tag);
        result.year = gSymbols.getYear(tag);
        
        // Read audio properties if available
        if (gSymbols.fileAudioProperties) {
            const TagLib_AudioProperties *props = gSymbols.fileAudioProperties(file);
            if (props) {
                if (gSymbols.apGetLength) {
                    result.duration = gSymbols.apGetLength(props);
                }
                if (gSymbols.apGetBitrate) {
                    result.bitrate = gSymbols.apGetBitrate(props);
                }
                if (gSymbols.apGetSampleRate) {
                    result.sampleRate = gSymbols.apGetSampleRate(props);
                }
                if (gSymbols.apGetChannels) {
                    result.channels = gSymbols.apGetChannels(props);
                }
            }
        }

        gSymbols.fileFree(file);
        [gTagLibLock unlock];
        return result;
    }
}

// MARK: - Write Metadata Implementation

BOOL TagLibBridgeWriteMetadata(NSString *path,
                               NSString * _Nullable title,
                               NSString * _Nullable artist,
                               NSString * _Nullable album,
                               NSString * _Nullable genre,
                               NSString * _Nullable year,
                               NSError * _Nullable * _Nullable error) {
    [gTagLibLock lock];
    @autoreleasepool {
        if (path.length == 0) {
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeInvalidInput
                                         userInfo:@{NSLocalizedDescriptionKey: @"无效的文件路径"}];
            }
            [gTagLibLock unlock];
            return NO;
        }

        if (!LoadTagLib(error)) {
            [gTagLibLock unlock];
            return NO;
        }

        TagLib_File *file = gSymbols.fileNew(path.fileSystemRepresentation);
        if (!file) {
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeOpenFile
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法打开音频文件"}];
            }
            [gTagLibLock unlock];
            return NO;
        }

        if (!gSymbols.fileIsValid(file)) {
            gSymbols.fileFree(file);
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeOpenFile
                                         userInfo:@{NSLocalizedDescriptionKey: @"音频文件无效或已损坏"}];
            }
            [gTagLibLock unlock];
            return NO;
        }

        TagLib_Tag *tag = gSymbols.fileTag(file);
        if (!tag) {
            gSymbols.fileFree(file);
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeOpenFile
                                         userInfo:@{NSLocalizedDescriptionKey: @"无法获取标签信息"}];
            }
            [gTagLibLock unlock];
            return NO;
        }

        SetTagString(gSymbols.setTitle, tag, title);
        SetTagString(gSymbols.setArtist, tag, artist);
        SetTagString(gSymbols.setAlbum, tag, album);
        SetTagString(gSymbols.setGenre, tag, genre);

        unsigned int yearValue = ParseUnsignedInteger(year ?: @"");
        gSymbols.setYear(tag, yearValue);

        BOOL success = gSymbols.fileSave(file);
        gSymbols.fileFree(file);

        if (!success) {
            if (error) {
                *error = [NSError errorWithDomain:TagLibBridgeErrorDomain
                                             code:TagLibBridgeErrorCodeSave
                                         userInfo:@{NSLocalizedDescriptionKey: @"写入音频标签失败"}];
            }
            [gTagLibLock unlock];
            return NO;
        }

        [gTagLibLock unlock];
        return YES;
    }
}
