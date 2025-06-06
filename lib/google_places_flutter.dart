library google_places_flutter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/place_type.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

import 'DioErrorHandler.dart';

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  const GooglePlaceAutoCompleteTextField({
    required this.textEditingController,
    required this.googleAPIKey,
    required this.onSelected,
    this.onSelectedWithLatLng,
    this.debounceTime = 600,
    this.inputDecoration = const InputDecoration(),
    this.textStyle = const TextStyle(),
    this.itemBuilder,
    this.boxDecoration,
    this.seperatedBuilder,
    this.padding,
    this.showError = true,
    this.focusNode,
    this.placeType,
    this.language = 'en',
    this.validator,
    this.countries = const [],
    this.latitude,
    this.longitude,
    this.radius,
    this.formSubmitCallback,
    this.textInputAction,
  });

  final InputDecoration inputDecoration;
  final void Function(Prediction prediction)? onSelected;

  /// If provided, will be called right after [onSelected],
  /// but with a Prediction where the latitude and longitude are provided.
  final void Function(Prediction prediction)? onSelectedWithLatLng;

  final TextStyle textStyle;
  final String googleAPIKey;
  final int debounceTime;
  final List<String>? countries;
  final TextEditingController textEditingController;
  final ListItemBuilder? itemBuilder;
  final Widget? seperatedBuilder;
  final BoxDecoration? boxDecoration;
  final bool showError;
  final EdgeInsets? padding;
  final FocusNode? focusNode;
  final PlaceType? placeType;
  final String? language;
  final TextInputAction? textInputAction;
  final VoidCallback? formSubmitCallback;

  final String? Function(String?, BuildContext)? validator;

  final double? latitude;
  final double? longitude;

  /// This is expressed in **meters**
  final int? radius;

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  late final FocusNode _focusNode;
  OverlayEntry? _overlayEntry;
  List<Prediction> predictions = [];

  final LayerLink _layerLink = LayerLink();

  final _dio = Dio();
  CancelToken? _cancelToken = CancelToken();

  @override
  void initState() {
    super.initState();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);

    // Add focus listener
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) removeOverlay();
    });
  }

  @override
  void dispose() {
    subject.close();
    _cancelToken?.cancel();
    removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: widget.padding,
        alignment: Alignment.centerLeft,
        decoration: widget.boxDecoration,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                decoration: widget.inputDecoration,
                style: widget.textStyle,
                controller: widget.textEditingController,
                focusNode: _focusNode,
                textInputAction: widget.textInputAction ?? TextInputAction.done,
                onFieldSubmitted: (value) {
                  if (widget.formSubmitCallback != null) {
                    widget.formSubmitCallback!();
                  }
                },
                validator: (inputString) {
                  return widget.validator?.call(inputString, context);
                },
                onChanged: subject.add,
              ),
            ),
          ],
        ),
      ),
    );
  }

  getLocation(String text) async {
    if (text.length == 0) return removeOverlay();

    String apiURL =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}&language=${widget.language}";

    if (widget.countries != null) {
      for (int i = 0; i < widget.countries!.length; i++) {
        String country = widget.countries![i];

        if (i == 0) {
          apiURL = apiURL + "&components=country:$country";
        } else {
          apiURL = apiURL + "|" + "country:" + country;
        }
      }
    }
    if (widget.placeType != null) {
      apiURL += "&types=${widget.placeType?.apiString}";
    }

    if (widget.latitude != null &&
        widget.longitude != null &&
        widget.radius != null) {
      apiURL = apiURL +
          "&location=${widget.latitude},${widget.longitude}&radius=${widget.radius}";
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }

    // print("urlll $apiURL");
    try {
      String proxyURL = "https://cors-anywhere.herokuapp.com/";
      String url = kIsWeb ? proxyURL + apiURL : apiURL;
      Response response = await _dio.get(url);

      if (widget.showError) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      predictions.clear();
      if (subscriptionResponse.predictions!.length > 0 &&
          (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        predictions.addAll(subscriptionResponse.predictions!);
      }

      this._overlayEntry?.remove();
      this._overlayEntry = this._createOverlayEntry();
      Overlay.of(context).insert(this._overlayEntry!);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  textChanged(String text) async {
    if (text.isNotEmpty) {
      getLocation(text);
    } else {
      predictions.clear();
      this._overlayEntry?.remove();
    }
  }

  OverlayEntry? _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: size.height + offset.dy,
        width: size.width,
        child: CompositedTransformFollower(
          showWhenUnlinked: false,
          link: this._layerLink,
          offset: Offset(0.0, size.height + 5.0),
          child: Material(
            elevation: 4,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: predictions.length,
              separatorBuilder: (context, pos) =>
                  widget.seperatedBuilder ?? SizedBox(),
              itemBuilder: (BuildContext context, int index) {
                return InkWell(
                  onTap: () {
                    var selectedData = predictions[index];
                    if (index < predictions.length) {
                      widget.onSelected!(selectedData);

                      if (widget.onSelectedWithLatLng != null) {
                        completeWithLatLng(selectedData);
                      }
                      removeOverlay();
                    }
                  },
                  child: widget.itemBuilder != null
                      ? widget.itemBuilder!(context, index, predictions[index])
                      : Container(
                          padding: EdgeInsets.all(10),
                          child: Text(predictions[index].description!),
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  removeOverlay() {
    predictions.clear();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> completeWithLatLng(Prediction prediction) async {
    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    try {
      Response response = await _dio.get(url);

      PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

      prediction.lat = placeDetails.result!.geometry!.location!.lat.toString();
      prediction.lng = placeDetails.result!.geometry!.location!.lng.toString();

      widget.onSelectedWithLatLng?.call(prediction);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  void _clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    removeOverlay();
  }

  _showSnackBar(String errorData) {
    if (widget.showError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("$errorData")));
    }
  }
}

typedef ListItemBuilder = Widget Function(
    BuildContext context, int index, Prediction prediction);
