import {CameraOptions, ImageLibraryOptions, Callback} from './types';
import {
  imageLibrary as nativeImageLibrary,
  camera as nativeCamera,
} from './platforms/native';

export * from './types';

export function launchCamera(
  options: CameraOptions,
  callback?: Callback,
) {
  return nativeCamera(options, callback);
}

export function launchImageLibrary(
  options: ImageLibraryOptions,
  callback?: Callback,
  onDidFinishPicking?: () => void,
) {
  return nativeImageLibrary(options, callback, onDidFinishPicking);
}
