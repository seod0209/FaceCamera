import React, {FC, useCallback, useEffect, useState} from 'react';
import {Linking, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {NativeStackScreenProps} from '@react-navigation/native-stack';

import {Camera, CameraPermissionStatus} from 'react-native-vision-camera';

import {GatherRouteParams} from '@/types/route.type';
import {ratioW} from '@/utils/dimension.util';

type Props = NativeStackScreenProps<GatherRouteParams, 'PERMISSION_STACK'>;

const PermissionPage: FC<Props> = ({navigation}) => {
  const [cameraPermissionStatus, setCameraPermissionStatus] =
    useState<CameraPermissionStatus>('not-determined');

  const requestCameraPermission = useCallback(async () => {
    const permission = Camera.getCameraPermissionStatus();

    if (permission !== 'granted') Linking.openSettings();

    setCameraPermissionStatus(permission);
  }, []);

  useEffect(() => {
    if (cameraPermissionStatus === 'granted') navigation.replace('HOME_STACK');
  }, [navigation]);

  return (
    <View style={styles.container}>
      <View>
        <Text style={styles.h1}>Oh!😲</Text>
        <Text>We cannot access your Camera.</Text>
      </View>
      {cameraPermissionStatus !== 'granted' && (
        <TouchableOpacity
          style={styles.button}
          onPress={requestCameraPermission}>
          <Text style={styles.buttonTxt}>Grant</Text>
        </TouchableOpacity>
      )}
    </View>
  );
};
export default PermissionPage;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    gap: ratioW(50),
  },
  h1: {
    fontSize: ratioW(32),
  },
  button: {
    padding: ratioW(8),
    borderWidth: 2,
    borderColor: '#007aff',
    borderRadius: 8,
  },
  buttonTxt: {
    color: '#007aff',
    fontSize: ratioW(28),
  },
});
