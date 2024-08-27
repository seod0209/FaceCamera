import React from 'react';
import {NavigationAction, NavigationContainer} from '@react-navigation/native';
import LottieSplashScreen from 'react-native-lottie-splash-screen';
import {navigationService} from '@/utils/navigation.util';
import {createNativeStackNavigator} from '@react-navigation/native-stack';

import {RootStackRouter, GatherRouteParams} from '@/constants/router.const';
import CameraPage from '@/screens/CameraPage';

const Stack = createNativeStackNavigator();

const RootRoutes = () => {
  const onNavigationReady = () => LottieSplashScreen.hide();
  return (
    <NavigationContainer
      onReady={onNavigationReady}
      ref={nav => (navigationService.navigator = nav)}>
      <Stack.Navigator>
        <Stack.Screen
          name={RootStackRouter.HOME_STACK}
          component={CameraPage}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
};

export default RootRoutes;
