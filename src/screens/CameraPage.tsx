import React, {useRef} from 'react';
import {StyleSheet, View, Text} from 'react-native';
import {Camera} from 'react-native-vision-camera';

const CameraPage = () => {
  const camera = useRef<Camera | null>(null);

  return (
    <View style={styles.container}>
      <Text>카메라에여</Text>
    </View>
  );
};

export default CameraPage;

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
});
