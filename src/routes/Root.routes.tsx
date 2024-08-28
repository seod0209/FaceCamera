import React, {useMemo} from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {Camera} from 'react-native-vision-camera';
import LottieSplashScreen from 'react-native-lottie-splash-screen';

import {navigationService} from '@/utils/navigation.util';
import {RootStackRouter} from '@/constants/router.const';

import CameraPage from '@/screens/CameraPage';
import PermissionPage from '@/screens/PermissionPage';
import {GatherRouteParams} from '@/types/route.type';

const Stack = createNativeStackNavigator<GatherRouteParams>();

const RootRoutes = () => {
  const cameraPermissionStatus = Camera.getCameraPermissionStatus();
  const isPermissioned = cameraPermissionStatus === 'granted';

  const initialRouteName = useMemo(
    () =>
      isPermissioned
        ? RootStackRouter.HOME_STACK
        : RootStackRouter.PERMISSION_STACK,
    [isPermissioned],
  );

  const onNavigationReady = () => LottieSplashScreen.hide();

  return (
    <NavigationContainer
      onReady={onNavigationReady}
      ref={nav => (navigationService.navigator = nav)}>
      <Stack.Navigator
        initialRouteName={initialRouteName}
        screenOptions={{headerShown: false}}>
        <Stack.Screen
          name={RootStackRouter.PERMISSION_STACK}
          component={PermissionPage}
        />
        <Stack.Screen
          name={RootStackRouter.HOME_STACK}
          component={CameraPage}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
};

export default RootRoutes;
