#import "ImagePickerUtils.h"
#import <CoreServices/CoreServices.h>
#import <PhotosUI/PhotosUI.h>

@implementation ImagePickerUtils

+ (void) setupPickerFromOptions:(UIImagePickerController *)picker options:(NSDictionary *)options
{   
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;

    if (options[@"durationLimit"] > 0) {
        picker.videoMaximumDuration = [options[@"durationLimit"] doubleValue];
    }

    if ([options[@"cameraType"] isEqualToString:@"front"]) {
        picker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
    } else {
        picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
    }

    if ([options[@"mediaType"] isEqualToString:@"video"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    } else if ([options[@"mediaType"] isEqualToString:@"photo"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeImage];
    } else if ([options[@"mediaType"] isEqualToString:@"mixed"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
    }

    picker.allowsEditing = YES;
    picker.modalPresentationStyle = [RCTConvert UIModalPresentationStyle:options[@"presentationStyle"]];
}

+ (PHPickerConfiguration *)makeConfigurationFromOptions:(NSDictionary *)options target:(RNImagePickerTarget)target API_AVAILABLE(ios(14))
{
    PHPickerConfiguration *configuration;
    
    PHPhotoLibrary *photoLibrary = [PHPhotoLibrary sharedPhotoLibrary];
    configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:photoLibrary];
    
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    configuration.selectionLimit = [options[@"selectionLimit"] integerValue];

    if ([options[@"mediaType"] isEqualToString:@"video"]) {
        configuration.filter = [PHPickerFilter videosFilter];
    } else if ([options[@"mediaType"] isEqualToString:@"photo"]) {
        configuration.filter = [PHPickerFilter imagesFilter];
    } else if ((target == library) && ([options[@"mediaType"] isEqualToString:@"mixed"])) {
        configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters: @[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
    }
    return configuration;
}


+ (BOOL) isSimulator
{
    #if TARGET_OS_SIMULATOR
        return YES;
    #endif
    return NO;
}

+ (NSString*) getFileType:(NSData *)imageData
{
    const uint8_t firstByteJpg = 0xFF;
    const uint8_t firstBytePng = 0x89;
    const uint8_t firstByteGif = 0x47;
    
    uint8_t firstByte;
    [imageData getBytes:&firstByte length:1];
    switch (firstByte) {
      case firstByteJpg:
        return @"jpg";
      case firstBytePng:
        return @"png";
      case firstByteGif:
        return @"gif";
      default:
        return @"jpg";
    }
}

+ (NSString *) getFileTypeFromUrl:(NSURL *)url {
    CFStringRef fileExtension = (__bridge CFStringRef)[url pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    return (__bridge_transfer NSString *)MIMEType;
}

+ (NSNumber *) getFileSizeFromUrl:(NSURL *)url {
    NSError *attributesError;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:&attributesError];
    NSNumber *fileSizeNumber = [fileAttributes objectForKey:NSFileSize];
    long fileSize = [fileSizeNumber longLongValue];

    if (attributesError) {
        return nil;
    }

    return [NSNumber numberWithLong:fileSize];
}

+ (CGSize)getVideoDimensionsFromUrl:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    
    if ([tracks count] > 0) {
        AVAssetTrack *track = [tracks objectAtIndex:0];
        return track.naturalSize;
    }
    
    return CGSizeMake(0, 0);
}

+ (UIImage *)getUIImageFromInfo:(NSDictionary *)info
{
    UIImage *image = info[UIImagePickerControllerEditedImage];
    if (!image) {
        image = info[UIImagePickerControllerOriginalImage];
    }
    return image;
}

@end
