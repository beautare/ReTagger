#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const TagLibBridgeErrorDomain;

typedef NS_ENUM(NSInteger, TagLibBridgeErrorCode) {
    TagLibBridgeErrorCodeOpenFile = 1,
    TagLibBridgeErrorCodeSave = 2,
    TagLibBridgeErrorCodeInvalidInput = 3,
    TagLibBridgeErrorCodeRead = 4
};

/// 元数据读取结果结构
@interface TagLibBridgeMetadataResult : NSObject
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSString *album;
@property (nonatomic, copy, nullable) NSString *genre;
@property (nonatomic, assign) NSUInteger year;
@property (nonatomic, assign) NSInteger bitrate;      // kbps
@property (nonatomic, assign) NSInteger sampleRate;   // Hz
@property (nonatomic, assign) NSInteger channels;
@property (nonatomic, assign) NSInteger duration;     // 秒
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 使用 TagLib 读取音频文件的元数据
/// @param path 音频文件路径
/// @param error 错误输出指针
/// @return 成功返回 TagLibBridgeMetadataResult，失败返回 nil
TagLibBridgeMetadataResult * _Nullable TagLibBridgeReadMetadata(NSString *path,
                                                                 NSError * _Nullable * _Nullable error);

/// 使用 TagLib 写入音频文件的元数据
BOOL TagLibBridgeWriteMetadata(NSString *path,
                               NSString * _Nullable title,
                               NSString * _Nullable artist,
                               NSString * _Nullable album,
                               NSString * _Nullable genre,
                               NSString * _Nullable year,
                               NSError * _Nullable * _Nullable error);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
