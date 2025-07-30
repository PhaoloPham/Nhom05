import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:users_app/authentication/login_screen.dart';
import 'package:users_app/global/global_var.dart';
import 'package:users_app/global/trip_var.dart';
import 'package:users_app/methods/common_methods.dart';
import 'package:users_app/models/direction_details.dart';
import 'package:users_app/models/prediction_model.dart';
import 'package:users_app/pages/about_page.dart';
import 'package:users_app/pages/search_destination_page.dart';
import 'package:users_app/pages/trips_history_page.dart';
import 'package:users_app/widgets/info_dialog.dart';
import 'package:users_app/widgets/payment_dialog.dart';
import '../appInfo/app_info.dart';
import '../widgets/loading_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TextEditingController pickUpTextEditingController = TextEditingController();
  TextEditingController destinationTextEditingController = TextEditingController();
  TextEditingController discountCodeController = TextEditingController();
  final Completer<GoogleMapController> googleMapCompleterController = Completer<GoogleMapController>();
  GoogleMapController? controllerGoogleMap;
  Position? currentPositionOfUser;
  GlobalKey<ScaffoldState> sKey = GlobalKey<ScaffoldState>();
  CommonMethods cMethods = CommonMethods();
  double searchContainerHeight = 276;
  double bottomMapPadding = 0;
  double rideDetailsContainerHeight = 0;
  double requestContainerHeight = 0;
  double tripContainerHeight = 0;
  DirectionDetails? tripDirectionDetailsInfo;
  List<LatLng> polylineCoOrdinates = [];
  List<PredictionModel> dropOffPredictionsPlacesList = [];
  Set<Polyline> polylineSet = {};
  Set<Marker> markerSet = {};
  Set<Circle> circleSet = {};
  bool isDrawerOpened = true;
  String stateOfApp = "normal";
  DatabaseReference? tripRequestRef;
  StreamSubscription<DatabaseEvent>? tripStreamSubscription;
  bool requestingDirectionDetailsInfo = false;
  double discountAmount = 0.0;
  String appliedDiscountCode = "";

  void updateMapTheme(GoogleMapController controller) {
    getJsonFileFromThemes("themes/retro_style.json")
        .then((value) => setGoogleMapStyle(value, controller));
  }

  Future<String> getJsonFileFromThemes(String mapStylePath) async {
    ByteData byteData = await rootBundle.load(mapStylePath);
    var list = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    return utf8.decode(list);
  }

  setGoogleMapStyle(String googleMapStyle, GoogleMapController controller) {
    controller.setMapStyle(googleMapStyle);
  }

  getCurrentLiveLocationOfUser() async {
    Position positionOfUser = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.bestForNavigation);
    currentPositionOfUser = positionOfUser;

    LatLng positionOfUserInLatLng = LatLng(currentPositionOfUser!.latitude, currentPositionOfUser!.longitude);

    CameraPosition cameraPosition = CameraPosition(target: positionOfUserInLatLng, zoom: 15);
    controllerGoogleMap!.animateCamera(CameraUpdate.newCameraPosition(cameraPosition));

    await CommonMethods.convertGeoGraphicCoOrdinatesIntoHumanReadableAddress(currentPositionOfUser!, context);

    await getUserInfoAndCheckBlockStatus();
  }

  getUserInfoAndCheckBlockStatus() async {
    DatabaseReference usersRef = FirebaseDatabase.instance.ref().child("users").child(FirebaseAuth.instance.currentUser!.uid);

    await usersRef.once().then((snap) {
      if (snap.snapshot.value != null) {
        if ((snap.snapshot.value as Map)["blockStatus"] == "no") {
          setState(() {
            userName = (snap.snapshot.value as Map)["name"];
            userPhone = (snap.snapshot.value as Map)["phone"];
          });
        } else {
          FirebaseAuth.instance.signOut();
          Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen()));
          cMethods.displaySnackBar("Bạn đã bị chặn! Liên hệ admin: CAOHUNGPHAM1804@gmail.com để được mở chặn", context);
        }
      } else {
        FirebaseAuth.instance.signOut();
        Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen()));
      }
    });
  }

  displayUserRideDetailsContainer() async {
    await retrieveDirectionDetails();

    setState(() {
      searchContainerHeight = 0;
      bottomMapPadding = 240;
      rideDetailsContainerHeight = 242;
      isDrawerOpened = false;
    });
  }

  retrieveDirectionDetails() async {
    var pickUpLocation = Provider.of<AppInfo>(context, listen: false).pickUpLocation;
    var dropOffLocation = Provider.of<AppInfo>(context, listen: false).dropOffLocation;

    var pickupGeoGraphicCoOrdinates = LatLng(pickUpLocation!.latitudePosition!, pickUpLocation.longitudePosition!);
    var dropOffGeoGraphicCoOrdinates = LatLng(dropOffLocation!.latitudePosition!, dropOffLocation.longitudePosition!);

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) => LoadingDialog(messageText: "Đang tìm hướng đi..."),
    );

    var detailsFromDirectionAPI = await CommonMethods.getDirectionDetailsFromAPI(pickupGeoGraphicCoOrdinates, dropOffGeoGraphicCoOrdinates);
    setState(() {
      tripDirectionDetailsInfo = detailsFromDirectionAPI;
    });

    Navigator.pop(context);

    PolylinePoints pointsPolyline = PolylinePoints();
    List<PointLatLng> latLngPointsFromPickUpToDestination = pointsPolyline.decodePolyline(tripDirectionDetailsInfo!.encodedPoints!);

    polylineCoOrdinates.clear();
    if (latLngPointsFromPickUpToDestination.isNotEmpty) {
      latLngPointsFromPickUpToDestination.forEach((PointLatLng latLngPoint) {
        polylineCoOrdinates.add(LatLng(latLngPoint.latitude, latLngPoint.longitude));
      });
    }

    polylineSet.clear();
    setState(() {
      Polyline polyline = Polyline(
        polylineId: const PolylineId("polylineID"),
        color: Colors.blue,
        points: polylineCoOrdinates,
        jointType: JointType.round,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      );

      polylineSet.add(polyline);
    });

    LatLngBounds boundsLatLng;
    if (pickupGeoGraphicCoOrdinates.latitude > dropOffGeoGraphicCoOrdinates.latitude &&
        pickupGeoGraphicCoOrdinates.longitude > dropOffGeoGraphicCoOrdinates.longitude) {
      boundsLatLng = LatLngBounds(
        southwest: dropOffGeoGraphicCoOrdinates,
        northeast: pickupGeoGraphicCoOrdinates,
      );
    } else if (pickupGeoGraphicCoOrdinates.longitude > dropOffGeoGraphicCoOrdinates.longitude) {
      boundsLatLng = LatLngBounds(
        southwest: LatLng(pickupGeoGraphicCoOrdinates.latitude, dropOffGeoGraphicCoOrdinates.longitude),
        northeast: LatLng(dropOffGeoGraphicCoOrdinates.latitude, pickupGeoGraphicCoOrdinates.longitude),
      );
    } else if (pickupGeoGraphicCoOrdinates.latitude > dropOffGeoGraphicCoOrdinates.latitude) {
      boundsLatLng = LatLngBounds(
        southwest: LatLng(dropOffGeoGraphicCoOrdinates.latitude, pickupGeoGraphicCoOrdinates.longitude),
        northeast: LatLng(pickupGeoGraphicCoOrdinates.latitude, dropOffGeoGraphicCoOrdinates.longitude),
      );
    } else {
      boundsLatLng = LatLngBounds(
        southwest: pickupGeoGraphicCoOrdinates,
        northeast: dropOffGeoGraphicCoOrdinates,
      );
    }

    controllerGoogleMap!.animateCamera(CameraUpdate.newLatLngBounds(boundsLatLng, 72));

    Marker pickUpPointMarker = Marker(
      markerId: const MarkerId("pickUpPointMarkerID"),
      position: pickupGeoGraphicCoOrdinates,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: pickUpLocation.placeName, snippet: "Pickup Location"),
    );

    Marker dropOffPointMarker = Marker(
      markerId: const MarkerId("dropOffDestinationPointMarkerID"),
      position: dropOffGeoGraphicCoOrdinates,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
      infoWindow: InfoWindow(title: dropOffLocation.placeName, snippet: "Destination Location"),
    );

    setState(() {
      markerSet.add(pickUpPointMarker);
      markerSet.add(dropOffPointMarker);
    });

    Circle pickUpPointCircle = Circle(
      circleId: const CircleId('pickupCircleID'),
      strokeColor: Colors.blue,
      strokeWidth: 4,
      radius: 14,
      center: pickupGeoGraphicCoOrdinates,
      fillColor: Colors.pink,
    );

    Circle dropOffPointCircle = Circle(
      circleId: const CircleId('dropOffDestinationCircleID'),
      strokeColor: Colors.blue,
      strokeWidth: 4,
      radius: 14,
      center: dropOffGeoGraphicCoOrdinates,
      fillColor: Colors.pink,
    );

    setState(() {
      circleSet.add(pickUpPointCircle);
      circleSet.add(dropOffPointCircle);
    });
  }

  resetAppNow() {
    setState(() {
      polylineCoOrdinates.clear();
      polylineSet.clear();
      markerSet.clear();
      circleSet.clear();
      rideDetailsContainerHeight = 0;
      requestContainerHeight = 0;
      tripContainerHeight = 0;
      searchContainerHeight = 276;
      bottomMapPadding = 300;
      isDrawerOpened = true;
      status = "";
      nameDriver = "";
      photoDriver = "";
      phoneNumberDriver = "";
      carDetailsDriver = "";
      tripStatusDisplay = 'Tài xế đã đến điểm hẹn';
      discountAmount = 0.0;
      appliedDiscountCode = "";
      discountCodeController.clear();
    });
  }

  cancelRideRequest() async {
    bool? confirmCancel = await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Xác nhận hủy chuyến"),
        content: const Text("Bạn có chắc chắn muốn hủy chuyến đi này?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Không"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Có"),
          ),
        ],
      ),
    );

    if (confirmCancel == true) {
      await tripRequestRef?.remove();
      tripStreamSubscription?.cancel();
      setState(() {
        stateOfApp = "normal";
        resetAppNow();
      });
      cMethods.displaySnackBar("Chuyến đi đã được hủy.", context);
    }
  }

  displayRequestContainer() {
    setState(() {
      rideDetailsContainerHeight = 0;
      requestContainerHeight = 220;
      bottomMapPadding = 200;
      isDrawerOpened = true;
    });

    makeTripRequest(isSimulatedDriver: true);
  }

  displayTripDetailsContainer() {
    setState(() {
      requestContainerHeight = 0;
      tripContainerHeight = 291;
      bottomMapPadding = 281;
    });
  }

  updateFromDriverCurrentLocationToPickUp(driverCurrentLocationLatLng) async {
    if (!requestingDirectionDetailsInfo) {
      requestingDirectionDetailsInfo = true;

      var userPickUpLocationLatLng = LatLng(currentPositionOfUser!.latitude, currentPositionOfUser!.longitude);

      var directionDetailsPickup = await CommonMethods.getDirectionDetailsFromAPI(driverCurrentLocationLatLng, userPickUpLocationLatLng);

      if (directionDetailsPickup == null) {
        return;
      }

      setState(() {
        tripStatusDisplay = "Tài xế sẽ đến trong - ${directionDetailsPickup.durationTextString}";
      });

      requestingDirectionDetailsInfo = false;
    }
  }

  updateFromDriverCurrentLocationToDropOffDestination(driverCurrentLocationLatLng) async {
    if (!requestingDirectionDetailsInfo) {
      requestingDirectionDetailsInfo = true;

      var dropOffLocation = Provider.of<AppInfo>(context, listen: false).dropOffLocation;
      var userDropOffLocationLatLng = LatLng(dropOffLocation!.latitudePosition!, dropOffLocation.longitudePosition!);

      var directionDetailsPickup = await CommonMethods.getDirectionDetailsFromAPI(driverCurrentLocationLatLng, userDropOffLocationLatLng);

      if (directionDetailsPickup == null) {
        return;
      }

      setState(() {
        tripStatusDisplay = "Đang đi tới điểm đến: - ${directionDetailsPickup.durationTextString}";
      });

      requestingDirectionDetailsInfo = false;
    }
  }

  searchLocation(String locationName) async {
    if (locationName.length > 1) {
      String apiPlacesUrl = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$locationName&key=$googleMapKey&components=country:vn";

      var responseFromPlacesAPI = await CommonMethods.sendRequestToAPI(apiPlacesUrl);

      if (responseFromPlacesAPI == "error") {
        return;
      }

      if (responseFromPlacesAPI["status"] == "OK") {
        var predictionResultInJson = responseFromPlacesAPI["predictions"];
        var predictionsList = (predictionResultInJson as List)
            .map((eachPlacePrediction) => PredictionModel.fromJson(eachPlacePrediction))
            .toList();

        setState(() {
          dropOffPredictionsPlacesList = predictionsList;
        });
      }
    }
  }

  void simulateTripProgress() {
    if (tripRequestRef != null) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            status = "arrived";
            tripStatusDisplay = "Tài xế đã đến điểm hẹn";
          });
          tripRequestRef!.update({"status": "arrived"});
          cMethods.displaySnackBar("Tài xế đã đến điểm đón!", context);
        }
      });

      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            status = "ontrip";
            tripStatusDisplay = "Đang đi tới điểm đến";
          });
          tripRequestRef!.update({"status": "ontrip"});
        }
      });

      Future.delayed(const Duration(seconds: 15), () {
        if (mounted) {
          setState(() {
            status = "ended";
            tripStatusDisplay = "Chuyến đi đã kết thúc";
          });
          tripRequestRef!.update({"status": "ended"});
        }
      });
    }
  }

  void applyDiscountCode() async {
    String code = discountCodeController.text.trim();
    if (code.isEmpty) {
      cMethods.displaySnackBar("Vui lòng nhập mã giảm giá.", context);
      return;
    }

    DatabaseReference discountRef = FirebaseDatabase.instance.ref().child("discountCodes").child(code);
    var snapshot = await discountRef.get();

    if (snapshot.exists) {
      var discountData = snapshot.value as Map;
      double discountValue = double.parse(discountData["amount"].toString());
      setState(() {
        discountAmount = discountValue;
        appliedDiscountCode = code;
      });
      cMethods.displaySnackBar("Áp dụng mã giảm giá thành công! Giảm $discountValue đ.", context);
    } else {
      cMethods.displaySnackBar("Mã giảm giá không hợp lệ.", context);
    }
  }

  makeTripRequest({bool isSimulatedDriver = false}) async {
    tripRequestRef = FirebaseDatabase.instance.ref().child("tripRequests").push();

    var pickUpLocation = Provider.of<AppInfo>(context, listen: false).pickUpLocation;
    var dropOffLocation = Provider.of<AppInfo>(context, listen: false).dropOffLocation;

    Map pickUpCoOrdinatesMap = {
      "latitude": pickUpLocation!.latitudePosition.toString(),
      "longitude": pickUpLocation.longitudePosition.toString(),
    };

    Map dropOffDestinationCoOrdinatesMap = {
      "latitude": dropOffLocation!.latitudePosition.toString(),
      "longitude": dropOffLocation.longitudePosition.toString(),
    };

    Map driverCoOrdinates = {
      "latitude": isSimulatedDriver ? (currentPositionOfUser!.latitude + 0.001).toString() : "",
      "longitude": isSimulatedDriver ? (currentPositionOfUser!.longitude + 0.001).toString() : "",
    };

    Map dataMap = {
      "tripID": tripRequestRef!.key,
      "publishDateTime": DateTime.now().toString(),
      "userName": userName,
      "userPhone": userPhone,
      "userID": userID,
      "pickUpLatLng": pickUpCoOrdinatesMap,
      "dropOffLatLng": dropOffDestinationCoOrdinatesMap,
      "pickUpAddress": pickUpLocation.placeName,
      "dropOffAddress": dropOffLocation.placeName,
      "driverID": isSimulatedDriver ? "simulated_driver_${tripRequestRef!.key}" : "waiting",
      "carDetails": isSimulatedDriver ? "Toyota Camry - 1234XYZ" : "",
      "driverLocation": driverCoOrdinates,
      "driverName": isSimulatedDriver ? "Phạm Cao Hùng" : "",
      "driverPhone": isSimulatedDriver ? "0393621532" : "",
      "driverPhoto": isSimulatedDriver ? "https://random.imagecdn.app/500/500" : "",
      "fareAmount": cMethods.calculateFareAmount(tripDirectionDetailsInfo!),
      "status": isSimulatedDriver ? "accepted" : "new",
      "discountCode": appliedDiscountCode,
      "discountAmount": discountAmount.toString(),
    };

    tripRequestRef!.set(dataMap);

    if (isSimulatedDriver) {
      displayTripDetailsContainer();

      setState(() {
        stateOfApp = "accepted";
        nameDriver = "Phạm Cao Hùng";
        phoneNumberDriver = "0393621532";
        carDetailsDriver = "Toyota Camry - 1234XYZ";
        photoDriver = "https://random.imagecdn.app/500/500";
        tripStatusDisplay = "Chuyến đi đã được chấp nhận";
      });

      tripRequestRef!.child("driverLocation").set({
        "latitude": (currentPositionOfUser!.latitude + 0.001).toString(),
        "longitude": (currentPositionOfUser!.longitude + 0.001).toString(),
      });

      simulateTripProgress();

      tripStreamSubscription = tripRequestRef!.onValue.listen((eventSnapshot) async {
        if (eventSnapshot.snapshot.value == null) {
          return;
        }

        if ((eventSnapshot.snapshot.value as Map)["status"] != null) {
          status = (eventSnapshot.snapshot.value as Map)["status"];
        }

        if ((eventSnapshot.snapshot.value as Map)["driverLocation"] != null) {
          double driverLatitude = double.parse((eventSnapshot.snapshot.value as Map)["driverLocation"]["latitude"].toString());
          double driverLongitude = double.parse((eventSnapshot.snapshot.value as Map)["driverLocation"]["longitude"].toString());
          LatLng driverCurrentLocationLatLng = LatLng(driverLatitude, driverLongitude);

          if (status == "accepted") {
            updateFromDriverCurrentLocationToPickUp(driverCurrentLocationLatLng);
          } else if (status == "arrived") {
            setState(() {
              tripStatusDisplay = "Tài xế đã đến điểm hẹn";
            });
          } else if (status == "ontrip") {
            updateFromDriverCurrentLocationToDropOffDestination(driverCurrentLocationLatLng);
          } else if (status == "ended") {
            if ((eventSnapshot.snapshot.value as Map)["fareAmount"] != null) {
              double fareAmount = double.parse((eventSnapshot.snapshot.value as Map)["fareAmount"].toString());
              fareAmount = (fareAmount - discountAmount) < 0 ? 0 : (fareAmount - discountAmount);

              String driverID = (eventSnapshot.snapshot.value as Map)["driverID"].toString();

              var responseFromPaymentDialog = await showDialog(
                context: context,
                builder: (BuildContext context) => PaymentDialog(fareAmount: fareAmount.toString(), driverID: driverID),
              );

              if (responseFromPaymentDialog == "paid") {
                tripRequestRef!.onDisconnect();
                tripRequestRef = null;
                resetAppNow();
              }
            }
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: sKey,
      drawer: Container(
        width: 255,
        color: Colors.white,
        child: Drawer(
          backgroundColor: Colors.white10,
          child: ListView(
            children: [
              const Divider(
                height: 1,
                color: Colors.grey,
                thickness: 1,
              ),
              Container(
                color: Colors.white,
                height: 160,
                child: DrawerHeader(
                  decoration: const BoxDecoration(
                    color: Colors.white10,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        "assets/images/avatarman.png",
                        width: 60,
                        height: 60,
                      ),
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Hồ sơ",
                        style: TextStyle(color: Colors.black),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => TripsHistoryPage()));
                },
                child: ListTile(
                  leading: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.history, color: Colors.black),
                  ),
                  title: const Text(
                    "Lịch sử",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => AboutPage()));
                },
                child: ListTile(
                  leading: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.info, color: Colors.black),
                  ),
                  title: const Text(
                    "Giới thiệu",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  FirebaseAuth.instance.signOut();
                  Navigator.push(context, MaterialPageRoute(builder: (c) => LoginScreen()));
                },
                child: ListTile(
                  leading: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.logout, color: Colors.black),
                  ),
                  title: const Text(
                    "Đăng xuất",
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          showMap(),
          Positioned(
            top: 36,
            left: 19,
            child: GestureDetector(
              onTap: () {
                if (isDrawerOpened == true) {
                  sKey.currentState!.openDrawer();
                } else {
                  resetAppNow();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 5,
                      spreadRadius: 0.5,
                      offset: Offset(0.7, 0.7),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 20,
                  child: Icon(
                    isDrawerOpened == true ? Icons.menu : Icons.close,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
          pickUpPlace(context),
          riderDetails(context),
          requestContainer(),
          tripDetails(),
        ],
      ),
    );
  }

  GoogleMap showMap() {
    return GoogleMap(
      padding: EdgeInsets.only(top: 26, bottom: bottomMapPadding),
      mapType: MapType.normal,
      myLocationEnabled: true,
      polylines: polylineSet,
      markers: markerSet,
      circles: circleSet,
      initialCameraPosition: googlePlexInitialPosition,
      onMapCreated: (GoogleMapController mapController) {
        controllerGoogleMap = mapController;
        updateMapTheme(controllerGoogleMap!);
        googleMapCompleterController.complete(controllerGoogleMap);
        setState(() {
          bottomMapPadding = 300;
        });
        getCurrentLiveLocationOfUser();
      },
    );
  }

  Positioned pickUpPlace(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 200,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const Icon(Icons.add_location_outlined, color: Colors.red),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Vị trí hiện tại",
                        style: TextStyle(color: Colors.black, fontSize: 12),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          Provider.of<AppInfo>(context, listen: false).pickUpLocation?.humanReadableAddress?.substring(9) ?? "Không thấy địa chỉ",
                          style: const TextStyle(color: Colors.black, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            const Divider(height: 1, thickness: 1, color: Colors.grey),
            const SizedBox(height: 16.0),
            Row(
              children: [
                const Icon(Icons.add_location_outlined, color: Colors.red),
                const SizedBox(width: 12.0),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Vị trí cần đến",
                      style: TextStyle(color: Colors.black, fontSize: 12),
                    ),
                    GestureDetector(
                      onTap: () async {
                        var responseFromSearchPage = await Navigator.push(
                            context, MaterialPageRoute(builder: (c) => SearchDestinationPage()));
                        if (responseFromSearchPage == "placeSelected") {
                          displayUserRideDetailsContainer();
                        }
                      },
                      child: const Text(
                        "Đi đâu?",
                        style: TextStyle(color: Colors.black, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            const Divider(height: 1, thickness: 1, color: Colors.grey),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }

  Positioned tripDetails() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: tripContainerHeight,
        decoration: const BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.white24,
              blurRadius: 15.0,
              spreadRadius: 0.5,
              offset: Offset(0.7, 0.7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tripStatusDisplay,
                    style: const TextStyle(fontSize: 19, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              const Divider(height: 1, color: Colors.white70, thickness: 1),
              const SizedBox(height: 19),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipOval(
                    child: Image.network(
                      photoDriver == '' ? "https://random.imagecdn.app/500/500" : photoDriver,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nameDriver,
                        style: const TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                      Text(
                        carDetailsDriver,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 19),
              const Divider(height: 1, color: Colors.white70, thickness: 1),
              const SizedBox(height: 19),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      launchUrl(Uri.parse("tel:$phoneNumberDriver"));
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          height: 50,
                          width: 50,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.circular(25)),
                            border: Border.all(width: 1, color: Colors.white),
                          ),
                          child: const Icon(Icons.phone, color: Colors.white),
                        ),
                        const SizedBox(height: 11),
                        const Text("Gọi tài xế", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Positioned requestContainer() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: requestContainerHeight,
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 15.0,
              spreadRadius: 0.5,
              offset: Offset(0.7, 0.7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: LoadingAnimationWidget.flickr(
                  leftDotColor: Colors.greenAccent,
                  rightDotColor: Colors.pinkAccent,
                  size: 50,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  cancelRideRequest();
                },
                child: Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(width: 1.5, color: Colors.grey),
                  ),
                  child: const Icon(Icons.close, color: Colors.black, size: 25),
                ),
              ),
              const SizedBox(height: 10),
              const Text("Hủy chuyến", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Positioned riderDetails(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: rideDetailsContainerHeight,
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
          boxShadow: [
            BoxShadow(
              color: Colors.white12,
              blurRadius: 15.0,
              spreadRadius: 0.5,
              offset: Offset(.7, .7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: SizedBox(
                  height: 220,
                  child: Card(
                    elevation: 10,
                    child: Container(
                      width: MediaQuery.of(context).size.width * .70,
                      color: Colors.black45,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 8, right: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    (tripDirectionDetailsInfo != null) ? tripDirectionDetailsInfo!.distanceTextString! : "",
                                    style: const TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    (tripDirectionDetailsInfo != null) ? tripDirectionDetailsInfo!.durationTextString! : "",
                                    style: const TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  stateOfApp = "requesting";
                                });
                                displayRequestContainer();
                              },
                              child: Image.asset(
                                "assets/images/uberexec.png",
                                height: 110,
                                width: 110,
                              ),
                            ),
                            Text(
                              (tripDirectionDetailsInfo != null)
                                  ? (cMethods.calculateFareAmount(tripDirectionDetailsInfo!) != null
                                      ? "${NumberFormat("#,###").format((double.parse(cMethods.calculateFareAmount(tripDirectionDetailsInfo!)) - discountAmount) * 24000)} đ"
                                      : "")
                                  : "",
                              style: const TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: discountCodeController,
                                      decoration: const InputDecoration(
                                        hintText: "Nhập mã giảm giá",
                                        hintStyle: TextStyle(color: Colors.grey),
                                        filled: true,
                                        fillColor: Colors.white12,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () {
                                      applyDiscountCode();
                                    },
                                    child: const Text("Áp dụng"),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}