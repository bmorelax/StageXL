part of stagexl;

class TextField extends InteractiveObject {

  String _text = "";
  TextFormat _defaultTextFormat = null;

  String _autoSize = TextFieldAutoSize.NONE;
  String _type = TextFieldType.DYNAMIC;

  int _caretIndex = 0;
  int _caretLine = 0;
  num _caretTime = 0.0;
  num _caretX = 0.0;
  num _caretY = 0.0;
  num _caretWidth = 0.0;
  num _caretHeight = 0.0;

  bool _wordWrap = false;
  bool _multiline = false;
  bool _displayAsPassword = false;
  bool _background = false;
  bool _border = false;
  String _passwordChar = "•";
  int _backgroundColor = 0xFFFFFF;
  int _borderColor = 0x000000;
  int _maxChars = 0;
  num _width = 100;
  num _height = 100;

  num _textWidth = 0.0;
  num _textHeight = 0.0;
  final List<TextLineMetrics> _textLineMetrics = new List<TextLineMetrics>();

  int _refreshPending = 3;   // bit 0: textLineMetrics, bit 1: cache
  bool _cacheAsBitmap = true;
  CanvasElement _cacheAsBitmapCanvas;

  //-------------------------------------------------------------------------------------------------

  TextField([String text, TextFormat textFormat]) {

    this.text = (text != null) ? text : "";
    this.defaultTextFormat = (textFormat != null) ? textFormat : new TextFormat("Arial", 12, 0x000000);

    this.onKeyDown.listen(_onKeyDown);
    this.onTextInput.listen(_onTextInput);
    this.onMouseDown.listen(_onMouseDown);
  }

  //-------------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------------

  String get text => _text;
  int get textColor => _defaultTextFormat.color;
  TextFormat get defaultTextFormat => _defaultTextFormat;

  int get caretIndex => _caretIndex;

  String get autoSize => _autoSize;
  String get type => _type;

  bool get wordWrap => _wordWrap;
  bool get multiline => _multiline;
  bool get displayAsPassword => _displayAsPassword;
  bool get background => _background;
  bool get border => _border;
  bool get cacheAsBitmap => _cacheAsBitmap;

  String get passwordChar => _passwordChar;
  int get backgroundColor => _backgroundColor;
  int get borderColor => _borderColor;
  int get maxChars => _maxChars;

  //-------------------------------------------------------------------------------------------------

  void set width(num value) {
    _width = value.toDouble();
    _refreshPending |= 3;
  }

  void set height(num value) {
    _height = value.toDouble();
    _refreshPending |= 3;
  }

  void set text(String value) {
    _text = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _caretIndex = _text.length;
    _refreshPending |= 3;
  }

  void set textColor(int value) {
    _defaultTextFormat.color = value;
    _refreshPending |= 2;
  }

  void set defaultTextFormat(TextFormat value) {
    _defaultTextFormat = value.clone();
    _refreshPending |= 3;
  }

  void set autoSize(String value) {
    _autoSize = value;
    _refreshPending |= 3;
  }

  void set type(String value) {
    _type = value;
    _refreshPending |= 3;
  }

  void set wordWrap(bool value) {
    _wordWrap = value;
    _refreshPending |= 3;
  }

  void set multiline(bool value) {
    _multiline = value;
    _refreshPending |= 3;
  }

  void set displayAsPassword(bool value) {
    _displayAsPassword = value;
    _refreshPending |= 3;
  }

  void set passwordChar(String value) {
    _passwordChar = value[0];
    _refreshPending |= 3;
  }

  void set background(bool value) {
    _background = value;
    _refreshPending |= 2;
  }

  void set backgroundColor(int value) {
    _backgroundColor = value;
    _refreshPending |= 2;
  }

  void set border(bool value) {
    _border = value;
    _refreshPending |= 2;
  }

  void set borderColor(int value) {
    _borderColor = value;
    _refreshPending |= 2;
  }

  void set maxChars(int value) {
    _maxChars = value;
  }

  void set cacheAsBitmap(bool value) {
    if (value) _refreshPending |= 2;
    _cacheAsBitmap = value;
  }

  //-------------------------------------------------------------------------------------------------

  num get x {
    _refreshTextLineMetrics();
    return super.x;
  }

  num get width {
    _refreshTextLineMetrics();
    return _width;
  }

  num get height {
    _refreshTextLineMetrics();
    return _height;
  }

  num get textWidth {
    _refreshTextLineMetrics();
    return _textWidth;
  }

  num get textHeight {
    _refreshTextLineMetrics();
    return _textHeight;
  }

  int get numLines {
    _refreshTextLineMetrics();
    return _textLineMetrics.length;
  }

  TextLineMetrics getLineMetrics(int lineIndex) {
    _refreshTextLineMetrics();
    return _textLineMetrics[lineIndex];
  }

  String getLineText(int lineIndex) {
    return getLineMetrics(lineIndex)._text;
  }

  int getLineLength(int lineIndex) {
    return getLineText(lineIndex).length;
  }

  //-------------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------------

  Rectangle getBoundsTransformed(Matrix matrix, [Rectangle returnRectangle]) {
    return _getBoundsTransformedHelper(matrix, _width, _height, returnRectangle);
  }

  //-------------------------------------------------------------------------------------------------

  DisplayObject hitTestInput(num localX, num localY) {

    if (localX >= 0 && localY >= 0 && localX < _width && localY < _height)
      return this;

    return null;
  }

  //-------------------------------------------------------------------------------------------------

  void render(RenderState renderState) {

    _refreshTextLineMetrics();
    _refreshCache();

    // draw text

    var renderContext = renderState.context;

    if (_cacheAsBitmap) {
      renderContext.drawImageScaled(_cacheAsBitmapCanvas, 0.0, 0.0, _width, _height);
    } else {
      _renderText(renderContext);
    }

    // draw cursor for INPUT text fields

    _caretTime += renderState.deltaTime;

    if (_type == TextFieldType.INPUT) {
      var stage = this.stage;
      if (stage != null && stage.focus == this && _caretTime.remainder(0.8) < 0.4) {
        renderContext.fillStyle = _color2rgb(_defaultTextFormat.color);
        renderContext.fillRect(_caretX, _caretY, _caretWidth, _caretHeight);
      }
    }
  }

  //-------------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------------

  _refreshTextLineMetrics() {

    if ((_refreshPending & 1) == 0) {
      return;
    } else {
      _refreshPending &= 255 - 1;
    }

    _textLineMetrics.clear();

    //-----------------------------
    // split lines

    var startIndex = 0;
    var checkLine = '';
    var validLine = '';
    var lineWidth = 0;
    var lineIndent = 0;

    var textFormatSize = _ensureNum(_defaultTextFormat.size);
    var textFormatLeftMargin = _ensureNum(_defaultTextFormat.leftMargin);
    var textFormatRightMargin = _ensureNum(_defaultTextFormat.rightMargin);
    var textFormatTopMargin = _ensureNum(_defaultTextFormat.topMargin);
    var textFormatBottomMargin = _ensureNum(_defaultTextFormat.bottomMargin);
    var textFormatIndent = _ensureNum(_defaultTextFormat.indent);
    var textFormatLeading = _ensureNum(defaultTextFormat.leading);
    var textFormatAlign = _ensureString(_defaultTextFormat.align);

    var fontStyle = _defaultTextFormat._cssFontStyle;
    var fontStyleMetrics = _getFontStyleMetrics(fontStyle);
    var fontStyleMetricsAscent = _ensureNum(fontStyleMetrics.ascent);
    var fontStyleMetricsDescent = _ensureNum(fontStyleMetrics.descent);

    var availableWidth = _width - textFormatLeftMargin - textFormatRightMargin;
    var canvasContext = _dummyCanvasContext;
    var paragraphLines = new List<int>();

    canvasContext.font = fontStyle;
    canvasContext.textAlign = "start";
    canvasContext.textBaseline = "alphabetic";
    canvasContext.setTransform(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);

    for(var paragraph in _text.split('\n')) {

      paragraphLines.add(_textLineMetrics.length);

      if (_wordWrap == false) {

        _textLineMetrics.add(new TextLineMetrics._internal(paragraph, startIndex));
        startIndex += paragraph.length + 1;

      } else {

        checkLine = null;
        lineIndent = textFormatIndent;

        for(var word in paragraph.split(' ')) {

          validLine = checkLine;
          checkLine = (validLine == null) ? word : "$validLine $word";
          checkLine = _passwordEncoder(checkLine);
          lineWidth = canvasContext.measureText(checkLine).width.toDouble();

          if (lineIndent + lineWidth >= availableWidth) {
            if (validLine == null) {
              _textLineMetrics.add(new TextLineMetrics._internal(checkLine, startIndex));
              startIndex += checkLine.length + 1;
              checkLine = null;
              lineIndent = 0;
            } else {
              _textLineMetrics.add(new TextLineMetrics._internal(validLine, startIndex));
              startIndex += validLine.length + 1;
              checkLine = _passwordEncoder(word);
              lineIndent = 0;
            }
          }
        }

        if (checkLine != null) {
          _textLineMetrics.add(new TextLineMetrics._internal(checkLine, startIndex));
          startIndex += checkLine.length + 1;
        }
      }
    }

    //-----------------------------
    // calculate metrics

    _textWidth = 0.0;
    _textHeight = 0.0;

    for(int line = 0; line < _textLineMetrics.length; line++) {

      var textLineMetrics = _textLineMetrics[line];
      if (textLineMetrics is! TextLineMetrics) continue; // dart2js_hint

      var indent = paragraphLines.contains(line) ? textFormatIndent : 0;
      var offsetX = textFormatLeftMargin + indent;
      var offsetY = textFormatTopMargin + textFormatSize +
                    line * (textFormatLeading + textFormatSize + fontStyleMetricsDescent);

      var width = canvasContext.measureText(textLineMetrics._text).width.toDouble();

      switch(textFormatAlign) {
        case TextFormatAlign.CENTER:
        case TextFormatAlign.JUSTIFY:
          offsetX += (availableWidth - width) / 2;
          break;
        case TextFormatAlign.RIGHT:
        case TextFormatAlign.END:
          offsetX += (availableWidth - width);
          break;
      }

      textLineMetrics._x = offsetX;
      textLineMetrics._y = offsetY;
      textLineMetrics._width = width;
      textLineMetrics._height = textFormatSize;
      textLineMetrics._ascent = fontStyleMetricsAscent;
      textLineMetrics._descent = fontStyleMetricsDescent;
      textLineMetrics._leading = textFormatLeading;
      textLineMetrics._indent = indent;

      _textWidth = max(_textWidth, textFormatLeftMargin + indent + width + textFormatRightMargin);
      _textHeight = offsetY + fontStyleMetricsDescent + textFormatBottomMargin;
    }

    //-----------------------------
    // calculate autoSize

    var autoWidth = _wordWrap ? _width : _textWidth.ceil();
    var autoHeight = _textHeight.ceil();

    if (_width != autoWidth || _height != autoHeight) {

      switch(_autoSize) {
        case TextFieldAutoSize.LEFT:
          this.width = autoWidth;
          this.height = autoHeight;
          break;
        case TextFieldAutoSize.RIGHT:
          this.x = this.x - (autoWidth - _width);
          this.width = autoWidth;
          this.height = autoHeight;
          break;
        case TextFieldAutoSize.CENTER:
          this.x = this.x - (autoWidth - _width) / 2;
          this.width = autoWidth;
          this.height = autoHeight;
          break;
      }
    }

    //-----------------------------
    // calculate caret position

    if (_type == TextFieldType.INPUT) {

      for(int line = _textLineMetrics.length - 1; line >= 0; line--) {
        var textLineMetrics = _textLineMetrics[line];
        if (textLineMetrics is! TextLineMetrics) continue; // dart2js_hint

        if (_caretIndex >= textLineMetrics._textIndex) {
          var textIndex = _caretIndex - textLineMetrics._textIndex;
          var text = textLineMetrics._text.substring(0, textIndex);
          _caretLine = line;
          _caretX = textLineMetrics._x + canvasContext.measureText(text).width.toDouble();
          _caretY = textLineMetrics._y - fontStyleMetricsAscent * 0.9;
          _caretWidth = 1.0;
          _caretHeight = textFormatSize;
          break;
        }
      }

      var shiftX = 0.0;
      var shiftY = 0.0;

      while (shiftX + _caretX > _width) shiftX -= _width * 0.2;
      while (shiftX + _caretX < 0) shiftX += _width * 0.2;
      while (shiftY + _caretY + _caretHeight > _height) shiftY -= textFormatSize;
      while (shiftY + _caretY < 0) shiftY += textFormatSize;

      _caretX += shiftX;
      _caretY += shiftY;

      for(int line = 0; line < _textLineMetrics.length; line++) {
        var textLineMetrics = _textLineMetrics[line];
        if (textLineMetrics is! TextLineMetrics) continue; // dart2js_hint

        textLineMetrics._x += shiftX;
        textLineMetrics._y += shiftY;
      }
    }
  }

  //-------------------------------------------------------------------------------------------------

  _refreshCache() {

    if (_cacheAsBitmap && (_refreshPending & 2) == 2) {

      _refreshPending &= 255 - 2;

      var pixelRatio = (Stage.autoHiDpi ? _devicePixelRatio : 1.0) / _backingStorePixelRatio;
      var canvasWidth = (_width * pixelRatio).ceil();
      var canvasHeight =  (_height * pixelRatio).ceil();

      if (_cacheAsBitmapCanvas == null) {
        _cacheAsBitmapCanvas = new CanvasElement(width: canvasWidth, height: canvasHeight);
      }

      if (_cacheAsBitmapCanvas.width != canvasWidth) _cacheAsBitmapCanvas.width = canvasWidth;
      if (_cacheAsBitmapCanvas.height != canvasHeight) _cacheAsBitmapCanvas.height = canvasHeight;

      _cacheAsBitmapCanvas.context2D.setTransform(pixelRatio, 0.0, 0.0, pixelRatio, 0.0, 0.0);
      _cacheAsBitmapCanvas.context2D.clearRect(0, 0, _width, _height);

      _renderText(_cacheAsBitmapCanvas.context2D);
    }
  }

  //-------------------------------------------------------------------------------------------------

  _renderText(CanvasRenderingContext2D context) {

    context.save();
    context.beginPath();
    context.rect(0, 0, _width, _height);
    context.clip();

    context.font = _defaultTextFormat._cssFontStyle;
    context.textAlign = "start";
    context.textBaseline = "alphabetic";

    // draw background, text, border

    if (_background) {
      context.fillStyle = _color2rgb(_backgroundColor);
      context.fillRect(0, 0, _width, _height);
    }

    context.fillStyle = _color2rgb(_defaultTextFormat.color);

    for(int i = 0; i < _textLineMetrics.length; i++) {
      var lm = _textLineMetrics[i];
      context.fillText(lm._text, lm._x, lm._y);
    }

    if (_border) {
      context.strokeStyle = _color2rgb(_borderColor);
      context.lineWidth = 1;
      context.strokeRect(0, 0, _width, _height);
    }

    context.restore();
  }

  //-------------------------------------------------------------------------------------------------

  String _passwordEncoder(String text) {

    if (text is! String) return text;
    if (_displayAsPassword == false) return text;

    var newText = "";
    for(int i = 0; i < text.length; i++) {
      newText = "$newText$_passwordChar";
    }
    return newText;
  }

  //-------------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------------

  _onKeyDown(KeyboardEvent keyboardEvent) {

    if (_type == TextFieldType.INPUT) {

      _refreshTextLineMetrics();

      var text = _text;
      var textLength = text.length;
      var textLineMetrics = _textLineMetrics;
      var caretIndex = _caretIndex;
      var caretLine = _caretLine;
      var caretIndexNew = -1;

      switch(keyboardEvent.keyCode) {

        case html.KeyCode.BACKSPACE:
          if (caretIndex > 0) {
            _text = text.substring(0, caretIndex - 1) + text.substring(caretIndex);
            caretIndexNew = caretIndex - 1;
          }
          break;

        case html.KeyCode.END:
          var tlm = textLineMetrics[caretLine];
          caretIndexNew = tlm._textIndex + tlm._text.length;
          break;

        case html.KeyCode.HOME:
          var tlm = textLineMetrics[caretLine];
          caretIndexNew = tlm._textIndex;
          break;

        case html.KeyCode.LEFT:
          if (caretIndex > 0) {
            caretIndexNew = caretIndex - 1;
          }
          break;

        case html.KeyCode.UP:
          if (caretLine > 0 && caretLine < textLineMetrics.length) {
            var tlmFrom = textLineMetrics[caretLine ];
            var tlmTo = textLineMetrics[caretLine - 1];
            var lineIndex = min(caretIndex - tlmFrom._textIndex, tlmTo._text.length);
            caretIndexNew = tlmTo._textIndex + lineIndex;
          } else {
            caretIndexNew = 0;
          }
          break;

        case html.KeyCode.RIGHT:
          if (caretIndex < textLength) {
            caretIndexNew = caretIndex + 1;
          }
          break;

        case html.KeyCode.DOWN:
          if (caretLine >= 0 && caretLine < textLineMetrics.length - 1) {
            var tlmFrom = textLineMetrics[caretLine ];
            var tlmTo = textLineMetrics[caretLine + 1];
            var lineIndex = min(caretIndex - tlmFrom._textIndex, tlmTo._text.length);
            caretIndexNew = tlmTo._textIndex + lineIndex;
          } else {
            caretIndexNew = textLength;
          }
          break;

        case html.KeyCode.DELETE:
          if (caretIndex < textLength) {
            _text = text.substring(0, caretIndex) + text.substring(caretIndex + 1);
            caretIndexNew = caretIndex;
          }
          break;
      }

      if (caretIndexNew != -1) {
        _caretIndex = caretIndexNew;
        _caretTime = 0.0;
        _refreshPending |= 3;
      }
    }
  }

  //-------------------------------------------------------------------------------------------------

  _onTextInput(TextEvent textEvent) {

    if (_type == TextFieldType.INPUT) {

      var textLength = _text.length;
      var caretIndex = _caretIndex;
      var newText = textEvent.text;

      if (newText == '\r') newText = '\n';
      if (newText == '\n' && _multiline == false) newText = '';
      if (newText == '') return;
      if (_maxChars != 0 && textLength >= _maxChars) return;

      _text = _text.substring(0, caretIndex) + newText + _text.substring(caretIndex);
      _caretIndex = _caretIndex + newText.length;
      _caretTime = 0.0;
      _refreshPending |= 3;
    }
  }

  //-------------------------------------------------------------------------------------------------

  _onMouseDown(MouseEvent mouseEvent) {

    var mouseX = mouseEvent.localX.toDouble();
    var mouseY = mouseEvent.localY.toDouble();
    var canvasContext = _dummyCanvasContext;

    canvasContext.setTransform(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);

    for(int line = 0; line < _textLineMetrics.length; line++) {

      var textLineMetrics = _textLineMetrics[line];
      if (textLineMetrics is! TextLineMetrics) continue;  // dart2js_hint

      var text = textLineMetrics._text;
      var lineX = textLineMetrics._x;
      var lineY1 = textLineMetrics._y - textLineMetrics._ascent;
      var lineY2 = textLineMetrics._y + textLineMetrics._descent;

      if (lineY1 <= mouseY && lineY2 >= mouseY) {
        var bestDistance = double.INFINITY;
        var bestIndex = 0;

        for(var c = 0; c <= text.length; c++) {
          var width = canvasContext.measureText(text.substring(0, c)).width.toDouble();
          var distance = (lineX + width - mouseX).abs();
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = c;
          }
        }

        _caretIndex = textLineMetrics._textIndex + bestIndex;
        _caretTime = 0.0;
        _refreshPending |= 3;
      }
    }
  }
}
