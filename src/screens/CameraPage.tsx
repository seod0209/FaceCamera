import React, {FC, useRef} from 'react';
import {StyleSheet, View} from 'react-native';
import {Camera} from 'react-native-vision-camera';

const CameraPage: FC = () => {
  const camera = useRef<Camera | null>(null);
  return <View style={styles.container}></View>;
};

export default CameraPage;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#ffffff',
  },
});
