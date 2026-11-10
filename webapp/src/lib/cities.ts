// 观测地选择里的常用城市（度、米）。
export interface City {
  zh: string;
  en: string;
  lat: number;
  lon: number;
  height: number;
}

export const CITIES: City[] = [
  { zh: '北京', en: 'Beijing', lat: 39.904, lon: 116.407, height: 50 },
  { zh: '上海', en: 'Shanghai', lat: 31.23, lon: 121.474, height: 5 },
  { zh: '广州', en: 'Guangzhou', lat: 23.129, lon: 113.264, height: 20 },
  { zh: '成都', en: 'Chengdu', lat: 30.573, lon: 104.066, height: 500 },
  { zh: '西安', en: "Xi'an", lat: 34.341, lon: 108.94, height: 400 },
  { zh: '乌鲁木齐', en: 'Ürümqi', lat: 43.825, lon: 87.617, height: 800 },
  { zh: '拉萨', en: 'Lhasa', lat: 29.652, lon: 91.172, height: 3650 },
  { zh: '哈尔滨', en: 'Harbin', lat: 45.803, lon: 126.535, height: 150 },
  { zh: '香港', en: 'Hong Kong', lat: 22.32, lon: 114.17, height: 30 },
  { zh: '台北', en: 'Taipei', lat: 25.033, lon: 121.565, height: 10 },
  { zh: '东京', en: 'Tokyo', lat: 35.676, lon: 139.65, height: 40 },
  { zh: '新加坡', en: 'Singapore', lat: 1.352, lon: 103.82, height: 15 },
  { zh: '伦敦', en: 'London', lat: 51.507, lon: -0.128, height: 20 },
  { zh: '马德里', en: 'Madrid', lat: 40.417, lon: -3.704, height: 650 },
  { zh: '开罗', en: 'Cairo', lat: 30.044, lon: 31.236, height: 25 },
  { zh: '卢克索', en: 'Luxor', lat: 25.687, lon: 32.64, height: 80 },
  { zh: '纽约', en: 'New York', lat: 40.713, lon: -74.006, height: 10 },
  { zh: '悉尼', en: 'Sydney', lat: -33.869, lon: 151.209, height: 20 },
];
