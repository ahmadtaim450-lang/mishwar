// بيانات تجريبية للواجهة. لاحقاً بتنستبدل بـ API حقيقي.

enum RideKind { men, women, family }

class Person {
  final String name;
  final String initial;
  final String? image;
  final double rating;
  final int trips;
  final bool verified;
  const Person(this.name, this.initial, {this.image, this.rating = 4.8, this.trips = 10, this.verified = true});
}

class Trip {
  final String id;
  final String from, fromSpot, to, toSpot;
  final String dep, arr, duration;
  final int price;
  final int seatsLeft, seatsTotal;
  final Person driver;
  final String car;
  final RideKind kind;
  final bool instant;
  final List<String> stops;
  final int day; // 0 اليوم، 1 بكرا، سالب = بالماضي
  const Trip({
    required this.id,
    required this.from,
    required this.fromSpot,
    required this.to,
    required this.toSpot,
    required this.dep,
    required this.arr,
    required this.duration,
    required this.price,
    required this.seatsLeft,
    required this.seatsTotal,
    required this.driver,
    required this.car,
    this.kind = RideKind.men,
    this.instant = false,
    this.stops = const [],
    this.day = 1,
  });
}

const samer = Person('سامر', 'س', image: 'avatar_samer', rating: 4.9, trips: 38);
const abuSami = Person('أبو سامي', 'أ', image: 'avatar_abu', rating: 4.8, trips: 52);
const hussam = Person('حسام', 'ح', image: 'avatar_hussam', rating: 4.6, trips: 6);
const reem = Person('ريم', 'ر', image: 'avatar_reem', rating: 5.0, trips: 21);
const noorDriver = Person('أم أحمد', 'أ', image: 'avatar_noor', rating: 4.9, trips: 17);
const mazen = Person('مازن', 'م', rating: 4.8, trips: 14);
const me = Person('إيهاب', 'إ', rating: 4.9, trips: 12);

const trips = <Trip>[
  Trip(id: 't1', from: 'اللاذقية', fromSpot: 'الكورنيش الجنوبي', to: 'دمشق', toSpot: 'كراجات البرامكة', dep: '07:00', arr: '11:15', duration: '4 س 15 د', price: 75000, seatsLeft: 2, seatsTotal: 3, driver: samer, car: 'كيا ريو · فضي', stops: ['طرطوس', 'حمص'], instant: true),
  Trip(id: 't2', from: 'اللاذقية', fromSpot: 'الدوار الأزرق', to: 'دمشق', toSpot: 'المزة', dep: '08:30', arr: '12:40', duration: '4 س 10 د', price: 80000, seatsLeft: 1, seatsTotal: 3, driver: reem, car: 'هيونداي أكسنت · أبيض', kind: RideKind.women, stops: ['حمص']),
  Trip(id: 't3', from: 'جبلة', fromSpot: 'المدخل الشمالي', to: 'دمشق', toSpot: 'باب توما', dep: '10:00', arr: '14:20', duration: '4 س 20 د', price: 70000, seatsLeft: 3, seatsTotal: 4, driver: abuSami, car: 'شيري تيغو · رمادي', kind: RideKind.family, stops: ['طرطوس', 'حمص']),
  Trip(id: 't4', from: 'اللاذقية', fromSpot: 'الزراعة', to: 'دمشق', toSpot: 'كفرسوسة', dep: '14:15', arr: '18:30', duration: '4 س 15 د', price: 85000, seatsLeft: 2, seatsTotal: 3, driver: hussam, car: 'تويوتا كورولا · أسود', stops: ['حمص']),
  Trip(id: 't5', from: 'اللاذقية', fromSpot: 'الدوار الأزرق', to: 'حمص', toSpot: 'الإنشاءات', dep: '09:00', arr: '11:00', duration: 'ساعتين', price: 45000, seatsLeft: 2, seatsTotal: 3, driver: noorDriver, car: 'كيا بيكانتو · أحمر', kind: RideKind.women),
];

class City {
  final String name, sub, image;
  const City(this.name, this.sub, this.image);
}

const cities = <City>[
  City('دمشق', 'كراجات البرامكة · المزة · باب توما', 'city_damascus'),
  City('حلب', 'كراج الراموسة · الجميلية', 'city_aleppo'),
  City('اللاذقية', 'الكورنيش · الدوار الأزرق · الزراعة', 'city_latakia'),
  City('حمص', 'كراج حمص الجديد · الإنشاءات', 'city_homs'),
  City('طرطوس', 'الكورنيش البحري · كراج الانطلاق', 'city_tartus'),
  City('حماة', 'ساحة العاصي · كراج البولمان', 'city_hama'),
  City('جبلة', 'المدخل الشمالي · الكراج', 'city_jableh'),
  City('درعا', 'الكراج الجنوبي', 'city_daraa'),
];

class Review {
  final String name, initial, text, date;
  final int stars;
  const Review(this.name, this.initial, this.stars, this.text, this.date);
}

const reviews = <Review>[
  Review('مازن', 'م', 5, 'سواقة هادية ووصلنا عالوقت، والسيارة نضيفة ومكيّفة.', 'أيلول 2026'),
  Review('حسام', 'ح', 5, 'محترم كتير وانتظرني كم دقيقة بلا ما يتضايق.', 'أيلول 2026'),
  Review('أبو سامي', 'أ', 5, 'وقف للصلاة عالطريق، الله يجزيه الخير.', 'آب 2026'),
  Review('خالد', 'خ', 4, 'كلشي منيح، بس الاستراحة طوّلت شوي.', 'تموز 2026'),
];

class ChatMsg {
  final bool me;
  final String text, time;
  const ChatMsg(this.me, this.text, this.time);
}

const chatSeed = <ChatMsg>[
  ChatMsg(true, 'السلام عليكم، حجزت مقعد معك لبكرا', '18:02'),
  ChatMsg(false, 'وعليكم السلام، أهلين. تم القبول، الانطلاق 7 بالزبط من جنب الكورنيش الجنوبي', '18:05'),
  ChatMsg(true, 'تمام، معي شنتاية صغيرة بس', '18:06'),
  ChatMsg(false, 'ولا يهمك، في محل', '18:07'),
];

String money(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${b.toString()} ل.س';
}

String kindLabel(RideKind k) => switch (k) { RideKind.men => 'رجال', RideKind.women => 'نسائية', RideKind.family => 'عائلية' };
