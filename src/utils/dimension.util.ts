import {Dimensions, PixelRatio, Platform, StatusBar} from 'react-native';
import {isIPhoneX} from './device.util';

const {width} = Dimensions.get('screen');

export const screenWidth = Dimensions.get('window').width;
export const screenHeight = Dimensions.get('window').height;

// Reference screen width. Standard design resolution: 414
export const dSizeWidth = 414;

export const ratioW = (_width: number) => {
  return (_width * width) / dSizeWidth;
};

// Consider the top notch and safe area for iPhone X
export const ifIphoneX = (iPhoneXstyle: number, regularStyle: number) => {
  if (isIPhoneX()) {
    return iPhoneXstyle;
  }
  return regularStyle;
};

export const getStatusBarHeight = (safe: boolean) => {
  return Platform.select({
    ios: ifIphoneX(safe ? ratioW(72) : ratioW(56), ratioW(72)),
    android: StatusBar.currentHeight,
  });
};

export const fontSizeText = (size: number) => {
  const scaleFont = width / dSizeWidth;
  const newSize = size * scaleFont;

  if (Platform.OS === 'ios') {
    return Math.round(PixelRatio.roundToNearestPixel(newSize));
  } else {
    return Math.round(PixelRatio.roundToNearestPixel(newSize)) - 1;
  }
};

export const DEFAULT_ICON_SIZE = {
  width: ratioW(24),
  height: ratioW(24),
};
