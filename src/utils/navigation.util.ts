import {type NavigationContainerRef} from '@react-navigation/native';

export const navigationService: {
  navigator?: NavigationContainerRef<any> | null;
} = {
  navigator: null,
};

export function goBack(): void {
  const {navigator} = navigationService;

  if (!navigator) {
    console.warn('Navigation Contianer reference is not set.');
    return;
  }

  if (navigator.canGoBack()) {
    navigator.goBack();
  } else {
    console.warn('No screen to go back to.');
  }
}
