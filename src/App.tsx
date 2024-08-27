/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React from 'react';

import {SafeAreaView, ScrollView, useColorScheme, View} from 'react-native';

import {Colors} from 'react-native/Libraries/NewAppScreen';
import {useCameraDevice, useCameraPermission} from 'react-native-vision-camera';

import * as Sentry from '@sentry/react-native';

import {ThemeProvider} from 'styled-components';

import {theme} from './themes';
import RootRoutes from './routes/Root.routes';
import bootstrapApp from './utils/bootstrapApp.util';

bootstrapApp();

function App(): React.JSX.Element {
  const isDarkMode = useColorScheme() === 'dark';

  const device = useCameraDevice('back');
  const {hasPermission, requestPermission} = useCameraPermission();

  console.log(device, hasPermission);

  const backgroundStyle = {
    flex: 1,
    backgroundColor: isDarkMode ? Colors.darker : Colors.lighter,
  };

  return (
    <ThemeProvider theme={theme}>
      <SafeAreaView style={backgroundStyle}>
        <RootRoutes />
      </SafeAreaView>
    </ThemeProvider>
  );
}

export default Sentry.wrap(App);
