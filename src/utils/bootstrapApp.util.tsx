import Config from 'react-native-config';
import {UIManager} from 'react-native';
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
    UIManager.setLayoutAnimationEnabledExperimental(true);
  }

  enableScreens();
}

export default bootstrapApp;
