import {CameraOptions, ImageLibraryOptions, Callback} from './types';
import {
  imageLibrary as nativeImageLibrary,
  camera as nativeCamera,
} from './platforms/native';

export * from './types';

export function launchCamera(
  options: CameraOptions,
  callback?: Callback,
  onDidFinishPicking?: () => void,
) {
  return nativeCamera(options, callback, onDidFinishPicking);
}

export function launchImageLibrary(
  options: ImageLibraryOptions,
  callback?: Callback,
  onDidFinishPicking?: () => void,
) {
  return nativeImageLibrary(options, callback, onDidFinishPicking);
}
