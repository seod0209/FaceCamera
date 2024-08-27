export const colors = {
  blackAlpha: {
    default: '#000000',
    50: '#0000000a',
    100: '#0000000f',
    200: '#00000014',
    300: '#00000029',
    400: '#0000003d',
    500: '#0000005c',
    600: '#0000007a',
    700: '#000000a3',
    800: '#000000cc',
    900: '#000000eb',
  },
  gray: {
    50: '#f5f5f5',
    100: '#f0f0f0',
    200: '#ebebeb',
    300: '#d6d6d6',
    400: '#c2c2c2',
    500: '#a3a3a3',
    600: '#858585',
    700: '#5c5c5c',
    800: '#333333',
    900: '#141414',
  },
};

export function withOpacity(color: string, opacity: number): string {
  if ((__DEV__ && color.length !== 7) || opacity < 0 || opacity > 1) {
    return color;
  }
  const _opacity = Math.round(Math.min(Math.max(opacity || 1, 0), 1) * 255);
  return color + _opacity.toString(16).toUpperCase();
}
