import React from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';

import LottieSplashScreen from 'react-native-lottie-splash-screen';

import {navigationService} from '@/utils/navigation.util';
import {RootStackRouter} from '@/constants/router.const';

import CameraPage from '@/screens/CameraPage';

const Stack = createNativeStackNavigator();

const RootRoutes = () => {
  const onNavigationReady = () => LottieSplashScreen.hide();

  return (
    <NavigationContainer
      onReady={onNavigationReady}
      ref={nav => (navigationService.navigator = nav)}>
      <Stack.Navigator
        initialRouteName={RootStackRouter.HOME_STACK}
        screenOptions={{headerShown: false}}>
        <Stack.Screen
          name={RootStackRouter.HOME_STACK}
          component={CameraPage}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
};

export default RootRoutes;
