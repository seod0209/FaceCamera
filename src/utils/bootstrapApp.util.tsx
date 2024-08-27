import Config from 'react-native-config';
import {
  KeyboardAvoidingView,
  ScrollView,
  Text,
  TouchableOpacity,
  UIManager,
} from 'react-native';
import {enableScreens} from 'react-native-screens';
import * as Sentry from '@sentry/react-native';

import {isAndroid} from './device.util';

// run this before any screen render(usually in App.js)
function bootstrapApp() {
  Sentry.init({
    dsn: __DEV__ ? '' : Config.SENTRY_DSN,
    // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
    // We recommend adjusting this value in production.
    tracesSampleRate: 1.0,
    _experiments: {
      // profilesSampleRate is relative to tracesSampleRate.
      // Here, we'll capture profiles for 100% of transactions.
      profilesSampleRate: 1.0,
    },
  });

  if (isAndroid && UIManager.setLayoutAnimationEnabledExperimental) {
    UIManager.setLayoutAnimationEnabledExperimental(true); // Enables layout animations. This setting applies only to the Android platform.
  }

  (ScrollView as any).defaultProps = {
    keyboardShouldPersistTaps: 'handled', // Ensures that the keyboard does not automatically dismiss when touching the scrollable area of the screen.
  };
  (KeyboardAvoidingView as any).defaultProps = {
    behavior: isAndroid ? 'none' : 'padding', // Determines how the keyboard avoids overlapping the screen content. On Android, it is set to 'none', while on iOS it is set to 'padding'.
  };
  (Text as any).defaultProps = {
    minimumFontScale: 1,
    maxFontSizeMultiplier: 1,
    underlineColorAndroid: 'transparent',
  };
  (TouchableOpacity as any).defaultProps = {
    activeOpacity: 0.5,
  };

  enableScreens();
}

export default bootstrapApp;
