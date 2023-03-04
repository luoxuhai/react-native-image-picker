import { NativeModules, NativeEventEmitter } from 'react-native';

import {
  CameraOptions,
  ImageLibraryOptions,
  Callback,
  ImagePickerResponse,
} from '../types';

const { DID_FINISH_PICKING } = NativeModules.ImagePickerManager.getConstants();
const Emitter = new NativeEventEmitter(NativeModules.ImagePickerManager);

const DEFAULT_OPTIONS: ImageLibraryOptions & CameraOptions = {
  mediaType: 'photo',
  cameraType: 'back',
  selectionLimit: 1,
  durationLimit: 0,
  presentationStyle: 'pageSheet',
  representationMode: 'auto',
};

export function camera(
  options: CameraOptions,
  callback?: Callback,
  onDidFinishPicking?: () => void,
): Promise<ImagePickerResponse> {

  return new Promise((resolve) => {
    const ev = Emitter.addListener(DID_FINISH_PICKING, () => onDidFinishPicking?.());

    NativeModules.ImagePickerManager.launchCamera(
      {...DEFAULT_OPTIONS, ...options},
      (result: ImagePickerResponse) => {
        if (callback) callback(result);
        ev.remove();
        resolve(result);
      },
    );
  });
}

export function imageLibrary(
  options: ImageLibraryOptions,
  callback?: Callback,
  onDidFinishPicking?: () => void,
): Promise<ImagePickerResponse> {
  return new Promise((resolve) => {
    const ev = Emitter.addListener(DID_FINISH_PICKING, () => onDidFinishPicking?.());

    NativeModules.ImagePickerManager.launchImageLibrary(
      {...DEFAULT_OPTIONS, ...options},
      (result: ImagePickerResponse) => {
        if (callback) callback(result);
        ev.remove();
        resolve(result);
      }
    );
  });
}
