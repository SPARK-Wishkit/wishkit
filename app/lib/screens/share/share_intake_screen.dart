import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ads/tag_search_banner.dart';
import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/aws/gql_runner.dart';
import '../../services/parsing_bridge.dart';
import '../../services/share_input.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/add_folder_dialog.dart';
import '../../widgets/diary_widgets.dart';

/// Shown when another app shares a product URL into this app.
class ShareIntakeScreen extends StatefulWidget {
  const ShareIntakeScreen({super.key, this.sharedUrl});

  final String? sharedUrl;

  @override
  State<ShareIntakeScreen> createState() => _ShareIntakeScreenState();
}

class _ShareIntakeScreenState extends State<ShareIntakeScreen> {
  final bridge = ParsingBridge();
  final urlCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final memoCtrl = TextEditingController();
  bool loading = false;
  bool saving = false;
  String? error;
  ParsedProductInfo? parsed;
  String? selectedListId;

  /// 태그 사진으로 찾았을 때의 결과(어디서 찾았는지 안내용). URL로 직접 읽으면 지운다.
  TagIdentifyResult? tagResult;
  bool identifying = false;

  /// 태그로 찾은 링크가 "확인 필요"(서버가 품번을 확인 못 함)일 때, 사용자가 같은 상품이라고
  /// 답하기 전까지는 저장하지 않는다.
  bool tagConfirmPending = false;

  /// "다른 상품이에요"를 눌렀을 때 결과에 남기는 표시(안내 문구를 고르는 데 쓴다).
  static const _tagRejectedNote = '검색으로 찾은 상품이 태그와 다르다고 하셨어요';

  /// 태그 사진으로 찾았을 때 그 사진. 저장할 때 함께 올려서 상세 페이지에서 다시 볼 수 있게 한다.
  Uint8List? tagPhoto;
  String tagPhotoMime = 'image/jpeg';

  /// 사용자가 직접 찍은 옷 사진. 있으면 저장할 때 올려서 상품의 대표 사진(쇼핑몰 사진 자리)으로 쓴다.
  Uint8List? clothesPhoto;
  String clothesPhotoMime = 'image/jpeg';

  /// 판매 페이지 없이 직접 기록하는 중인지(QR·검색으로 못 찾았거나, 사용자가 "직접 기록하기"를 누름).
  /// 이때는 옷 사진 자리를 보여 주고, 태그에서 읽은 상품명·가격을 자동으로 채운다.
  bool manualMode = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<AppStore>();
    // 리스트를 고르지 않으면 '전체'에만 저장된다(폴더 칩을 누르면 그 폴더로).
    selectedListId = 'all';
    final initial = widget.sharedUrl ?? store.pendingShareUrl;
    if (initial != null) {
      urlCtrl.text = ShareInput.normalize(initial);
      WidgetsBinding.instance.addPostFrameCallback((_) => _parse());
    }
  }

  @override
  void dispose() {
    urlCtrl.dispose();
    titleCtrl.dispose();
    priceCtrl.dispose();
    memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _parse({bool fromTag = false}) async {
    final input = urlCtrl.text.trim();
    if (input.isEmpty) return;
    setState(() {
      loading = true;
      error = null;
      if (!fromTag) {
        tagResult = null;
        tagConfirmPending = false;
        tagPhoto = null; // URL로 직접 읽으면 앞서 찍은 태그 사진과는 다른 상품일 수 있다.
      }
      // 링크로 읽으면 쇼핑몰 사진이 생긴다. 직접 찍은 옷 사진은 남겨 두되(카드에서 뺄 수 있음) 직접 기록은 끝.
      manualMode = false;
    });
    try {
      final info = input.contains('http') && !input.trim().contains(' ')
          ? await bridge.parseProductUrl(input)
          : await bridge.scrapShareInput(input);
      titleCtrl.text = info.name == '공유된 상품' ? '' : info.name;
      priceCtrl.text = info.price > 0 ? '${info.price}' : '';
      if (mounted) setState(() => parsed = info);
    } catch (e) {
      if (mounted) setState(() => error = '상품 정보를 읽지 못했어요');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ── 태그 사진으로 찾기 ──

  /// 카메라/앨범을 골라 사진 한 장을 받는다. 취소하면 null.
  ///
  /// 1280px · JPEG 75%로 줄인다 — 태그 글자와 QR을 읽기에 충분하고, 서버로 보내거나 저장하기에도 가볍다.
  Future<(Uint8List, String)?> _pickPhoto({required String cameraLabel}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(cameraLabel),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('앨범에서 고르기'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return null;
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
    } catch (_) {
      if (mounted) setState(() => error = '카메라나 사진을 열 수 없어요. 권한을 확인해 주세요');
      return null;
    }
    if (picked == null || !mounted) return null;
    final bytes = await picked.readAsBytes();
    if (!mounted) return null;
    return (bytes, _mimeTypeOf(picked));
  }

  Future<void> _pickTagPhoto() async {
    if (identifying || loading) return;
    final photo = await _pickPhoto(cameraLabel: '태그 사진 찍기');
    if (photo == null) return;
    await _identifyFromTag(photo.$1, photo.$2);
  }

  /// 옷 사진을 고른다. 저장할 때 올려서 상품의 대표 사진으로 쓴다(쇼핑몰 사진이 있어도 이 사진이 우선).
  Future<void> _pickClothesPhoto() async {
    if (saving) return;
    final photo = await _pickPhoto(cameraLabel: '옷 사진 찍기');
    if (photo == null) return;
    setState(() {
      clothesPhoto = photo.$1;
      clothesPhotoMime = photo.$2;
      error = null;
    });
  }

  void _removeClothesPhoto() => setState(() => clothesPhoto = null);

  /// 링크도 태그 사진도 없이, 옷 사진·이름·가격만으로 직접 기록을 시작한다(오프라인 매장 등).
  void _startManual() {
    final link = ShareInput.firstUrl(urlCtrl.text);
    setState(() {
      manualMode = true;
      error = null;
      tagConfirmPending = false;
      parsed = ParsedProductInfo(
        name: titleCtrl.text.trim().isEmpty ? '공유된 상품' : titleCtrl.text.trim(),
        price: 0,
        platform: tagResult?.brand ?? '직접 기록',
        image: '',
        productUrl: link ?? '',
        missingFields: const ['price', 'image_url'],
      );
    });
  }

  String _mimeTypeOf(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.heic') || path.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _identifyFromTag(Uint8List bytes, String mimeType) async {
    final store = context.read<AppStore>();
    setState(() {
      identifying = true;
      error = null;
      tagResult = null;
      tagConfirmPending = false;
    });
    TagIdentifyResult result;
    try {
      result = await store.identifyProductFromTag(bytes, mimeType: mimeType);
    } on TagIdentifyUnavailable {
      if (mounted) {
        setState(() {
          identifying = false;
          error = '태그 사진으로 찾기는 로그인 후 사용할 수 있어요';
        });
      }
      return;
    } on AwsDataException catch (e) {
      if (mounted) {
        setState(() {
          identifying = false;
          error = e.isNetwork
              ? e.toString()
              : '사진에서 상품을 찾지 못했어요. 잠시 후 다시 시도해 주세요';
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          identifying = false;
          error = '사진에서 상품을 찾지 못했어요. 잠시 후 다시 시도해 주세요';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      identifying = false;
      tagResult = result;
      tagPhoto = result.status == TagIdentifyStatus.notATag ? null : bytes;
      tagPhotoMime = mimeType;
    });

    switch (result.status) {
      case TagIdentifyStatus.notATag:
        setState(() => error = '상품 태그가 잘 보이게 다시 찍어 주세요');
      case TagIdentifyStatus.found:
      case TagIdentifyStatus.needsConfirm:
        // 링크로 찾은 결과는 항상 "이 상품이 맞나요?"를 묻고, 답하기 전에는 저장하지 않는다.
        setState(() => tagConfirmPending = true);
        urlCtrl.text = result.matchUrl!;
        if (result.hasMatchDetails) {
          // 엔진이 찾은 페이지에서 상품명·가격·사진까지 읽어 왔으면 다시 읽지 않는다(더 빠르고,
          // 우리 서버에는 빈 화면을 주는 몰도 보여 줄 수 있다).
          _fillFromMatch(result);
        } else {
          // 가격은 "URL로 담기"와 같은 경로로 읽는다. 못 읽은 칸은 엔진이 준 값으로 채운다.
          await _parse(fromTag: true);
          if (!mounted) return;
          if (titleCtrl.text.trim().isEmpty) {
            titleCtrl.text = result.matchName ?? result.suggestedName;
          }
          if (priceCtrl.text.trim().isEmpty && result.matchPrice != null) {
            priceCtrl.text = '${result.matchPrice}';
          }
        }
      case TagIdentifyStatus.notFound:
        context.read<AppStore>().recordTagFeedback(TagFeedbackAnswer.notFound, result);
        _fillFromTagOnly(result);
    }
  }

  /// 엔진이 찾은 페이지에서 읽어 온 상품명·가격·사진으로 입력칸을 채운다.
  void _fillFromMatch(TagIdentifyResult r) {
    manualMode = false;
    final price = r.matchPrice ?? 0;
    final regular = r.matchRegularPrice;
    titleCtrl.text = r.matchName!;
    priceCtrl.text = price > 0 ? '$price' : '';
    setState(() {
      parsed = ParsedProductInfo(
        name: r.matchName!,
        price: price,
        platform: r.matchHost ?? r.brand ?? '태그 사진',
        image: r.matchImage ?? '',
        productUrl: r.matchUrl!,
        originalPrice: regular != null && regular > price ? regular : null,
        missingFields: [if ((r.matchImage ?? '').isEmpty) 'image_url'],
        engineUsed: true,
      );
    });
  }

  /// 판매 페이지 없이 태그 정보만으로 직접 기록을 시작한다(QR·품번 검색 모두 실패, 또는 "다른 상품이에요").
  ///
  /// 태그에서 읽은 상품명·가격을 자동으로 채운다. 태그 가격은 보통 그 매장의 정가라서, 매장에서 본 상품을
  /// 기록하는 이 경우엔 그대로 쓰는 게 맞다. 이미 직접 기록 중이었다면 사용자가 입력한 칸은 덮어쓰지 않는다.
  /// 옷 사진 자리를 보여 주므로 사용자가 찍은 옷 사진이 대표 사진이 된다.
  void _fillFromTagOnly(TagIdentifyResult result) {
    final keepTyped = manualMode;
    final suggested = result.suggestedName.trim();
    final name = suggested.isNotEmpty ? suggested : result.tagOnlyName.trim();
    final tagPrice = result.tagPrice;
    final code = (result.productCode ?? '').trim();
    urlCtrl.clear();
    if (!keepTyped || titleCtrl.text.trim().isEmpty) titleCtrl.text = name;
    if (tagPrice != null && (!keepTyped || priceCtrl.text.trim().isEmpty)) {
      priceCtrl.text = '$tagPrice';
    } else if (!keepTyped) {
      priceCtrl.clear();
    }
    // 품번은 나중에 매장·온라인에서 다시 찾을 때 필요하다 — 메모에 남겨 둔다.
    if (code.isNotEmpty && !memoCtrl.text.contains(code)) {
      memoCtrl.text = memoCtrl.text.trim().isEmpty
          ? '품번 $code'
          : '${memoCtrl.text.trim()}\n품번 $code';
    }
    final finalName = titleCtrl.text.trim();
    setState(() {
      manualMode = true;
      parsed = ParsedProductInfo(
        name: finalName.isEmpty ? '공유된 상품' : finalName,
        price: tagPrice ?? 0,
        platform: result.brand ?? '직접 기록',
        image: '',
        productUrl: '',
        originalPrice: tagPrice,
        missingFields: [if (tagPrice == null) 'price', 'image_url'],
      );
    });
  }

  /// "확인 필요" 결과에 대한 사용자의 답.
  void _answerTagConfirm({required bool same}) {
    final r = tagResult;
    if (r == null) return;
    context.read<AppStore>().recordTagFeedback(
      same ? TagFeedbackAnswer.yes : TagFeedbackAnswer.no,
      r,
    );
    if (same) {
      setState(() {
        tagConfirmPending = false;
        error = null;
      });
      return;
    }
    // 다른 상품이라고 하면 링크는 버리고 태그 정보만 남긴다.
    setState(() {
      tagConfirmPending = false;
      error = null;
      tagResult = TagIdentifyResult(
        status: TagIdentifyStatus.notFound,
        brand: r.brand,
        productCode: r.productCode,
        productName: r.productName,
        color: r.color,
        tagPrice: r.tagPrice,
        officialDomain: r.officialDomain,
        note: _tagRejectedNote,
      );
    });
    // 태그의 브랜드·품번·가격으로 직접 기록을 시작한다.
    _fillFromTagOnly(r);
  }

  Future<void> _openTagMatch() async {
    final url = tagResult?.matchUrl;
    if (url == null) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) setState(() => error = '링크를 열 수 없어요');
  }

  /// 태그 사진으로 찾은 결과 안내 문구.
  List<String> _tagResultLines(TagIdentifyResult r) {
    final lines = <String>[];
    switch (r.status) {
      case TagIdentifyStatus.found:
        if (r.foundByQr) {
          lines.add('태그의 QR로 ${r.matchHost}에서 찾았어요');
        } else {
          lines.add(
            r.foundOnOfficialSite
                ? '브랜드 공식몰(${r.matchHost})에서 찾았어요'
                : '${r.matchHost}에서 찾았어요',
          );
        }
        lines.add(
          r.needsUserCheck
              ? '품번 없이 이름으로 찾았어요'
              : '페이지에서 품번까지 확인했어요',
        );
        if (tagConfirmPending) lines.add('아래 상품이 태그 상품과 같은지 확인해 주세요');
      case TagIdentifyStatus.needsConfirm:
        lines.add(
          r.foundByQr
              ? '태그의 QR이 ${r.matchHost ?? '이 페이지'}로 연결돼요'
              : '${r.matchHost ?? '쇼핑몰'}에서 찾은 상품이에요',
        );
        lines.add('페이지에서 품번은 확인하지 못했어요');
        if (tagConfirmPending) lines.add('아래 상품이 태그 상품과 같은지 확인해 주세요');
      case TagIdentifyStatus.notFound:
        if (r.note == _tagRejectedNote) {
          lines.add('태그에서 읽은 이름·가격으로 채웠어요. 옷 사진을 넣고 확인해서 저장해 주세요');
          break;
        }
        lines.add('판매 페이지는 찾지 못해서, 태그에서 읽은 이름·가격으로 채웠어요');
        lines.add('옷 사진을 넣고 확인해서 저장해 주세요');
        // 서버가 알려 준 이유(예: 시간이 모자람, 품번이 적힌 페이지가 없음) — 다시 시도할지 판단하게.
        final note = r.note?.trim();
        if (note != null && note.isNotEmpty) lines.add('이유: $note');
      case TagIdentifyStatus.notATag:
        break;
    }
    if (r.hasMatchDetails && r.status != TagIdentifyStatus.notFound) {
      lines.add('가격은 검색 기준이라 지금 판매가와 다를 수 있어요');
    }
    if (r.productCode != null) lines.add('품번 ${r.productCode}');
    if (r.tagPrice != null && r.status != TagIdentifyStatus.notFound) {
      lines.add('태그 가격 ${formatWon(r.tagPrice!)} (정가라서 지금 판매가와 다를 수 있어요)');
    }
    return lines;
  }

  Future<void> _save() async {
    if (parsed == null || selectedListId == null || saving) return;
    if (tagConfirmPending) {
      setState(() => error = '태그와 같은 상품인지 먼저 확인해 주세요');
      return;
    }
    final name = titleCtrl.text.trim().isEmpty
        ? parsed!.name
        : titleCtrl.text.trim();
    final price =
        int.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (name.isEmpty || name == '공유된 상품') {
      setState(() => error = '상품명을 입력해 주세요');
      return;
    }
    if (price <= 0) {
      setState(() => error = '가격을 입력해 주세요');
      return;
    }

    // 페이지에서 주소를 못 얻었으면 입력칸의 첫 URL 만 쓴다(입력칸 글 전체를 넣지 않는다).
    // 직접 기록은 주소가 없어도 된다 — URL이 아닌 글자를 주소로 저장하지 않는다.
    final productUrl = parsed!.productUrl.isNotEmpty
        ? parsed!.productUrl
        : manualMode
        ? (ShareInput.firstUrl(urlCtrl.text) ?? '')
        : (ShareInput.firstUrl(urlCtrl.text) ?? urlCtrl.text.trim());
    final info = ParsedProductInfo(
      name: name,
      price: price,
      platform: parsed!.platform,
      image: parsed!.image,
      productUrl: productUrl,
      originalPrice: parsed!.originalPrice,
      discount: parsed!.discount,
      missingFields: [if (parsed!.image.isEmpty) 'image_url'],
      engineUsed: parsed!.engineUsed,
      purchasePriceStatus: parsed!.purchasePriceStatus,
      priceConfidence: parsed!.priceConfidence,
      extractFailureReason: parsed!.extractFailureReason,
    );

    setState(() {
      saving = true;
      error = null;
    });
    try {
      final store = context.read<AppStore>();
      // 옷 사진이 있으면 먼저 올려서 대표 사진으로 쓴다. 실패하면 원래 사진(없으면 빈 사진)으로 저장한다.
      String? clothesImageUrl;
      var clothesPhotoFailed = false;
      final clothes = clothesPhoto;
      if (clothes != null) {
        try {
          clothesImageUrl = await store.uploadProductPhoto(
            clothes,
            mimeType: clothesPhotoMime,
          );
        } catch (_) {
          clothesPhotoFailed = true;
        }
      }
      final toSave = clothesImageUrl == null
          ? info
          : ParsedProductInfo(
              name: info.name,
              price: info.price,
              platform: info.platform,
              image: clothesImageUrl,
              productUrl: info.productUrl,
              originalPrice: info.originalPrice,
              discount: info.discount,
              missingFields: const [],
              engineUsed: info.engineUsed,
              purchasePriceStatus: info.purchasePriceStatus,
              priceConfidence: info.priceConfidence,
              extractFailureReason: info.extractFailureReason,
            );

      // 태그 사진이 있으면 먼저 올린다. 실패해도 상품은 저장하고, 사진만 빠졌다고 알려 준다.
      String? tagImageUrl;
      var tagPhotoFailed = false;
      final photo = tagPhoto;
      if (photo != null) {
        try {
          tagImageUrl = await store.uploadTagPhoto(photo, mimeType: tagPhotoMime);
        } catch (_) {
          tagPhotoFailed = true;
        }
      }
      final uploadedTag = tagImageUrl;
      final uploadedClothes = clothesImageUrl;
      Future<void> discardUploads() async {
        if (uploadedTag != null) await store.discardTagPhoto(uploadedTag);
        if (uploadedClothes != null) {
          await store.discardProductPhoto(uploadedClothes);
        }
      }

      final Product? product;
      try {
        product = await store.addParsedProduct(
          toSave,
          listId: selectedListId!,
          memo: memoCtrl.text,
          tagImageUrl: tagImageUrl,
        );
      } catch (_) {
        // 상품 저장이 실패하면 방금 올린 사진들은 쓸 곳이 없으니 지운다.
        await discardUploads();
        rethrow;
      }
      if (product == null) {
        // 같은 상품을 이미 저장하는 중(연타) — 이번에 올린 사진은 쓰이지 않는다.
        await discardUploads();
        return;
      }
      store.setPendingShareUrl(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch ((clothesPhotoFailed, tagPhotoFailed)) {
              (true, true) => '${product.name} 을(를) 저장했어요. 옷 사진과 태그 사진은 저장하지 못했어요',
              (true, false) => '${product.name} 을(를) 저장했어요. 옷 사진은 저장하지 못했어요',
              (false, true) => '${product.name} 을(를) 저장했어요. 태그 사진은 저장하지 못했어요',
              (false, false) => '${product.name} 을(를) 저장했어요',
            }),
          ),
        );
        context.go('/');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _statusText(ParsedProductInfo info) {
    if (manualMode) {
      return tagResult != null && tagResult!.status != TagIdentifyStatus.notATag
          ? '직접 기록 · 태그에서 읽은 값을 채웠어요'
          : '직접 기록';
    }
    switch (info.extractFailureReason) {
      case ExtractFailureReason.notLoggedIn:
        return '로그인하면 상품 정보를 자동으로 읽어요. 지금은 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.engineOff:
        return '지금은 자동 읽기 서버가 꺼져 있어요. 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.timeout:
        return '페이지를 읽는 데 시간이 너무 걸렸어요. 다시 시도하거나 직접 입력해 주세요.';
      case ExtractFailureReason.network:
        return '인터넷 연결을 확인해 주세요. 이름과 가격은 직접 입력할 수 있어요.';
      case ExtractFailureReason.failed:
        return '이 페이지는 자동으로 읽지 못했어요. 이름과 가격을 직접 입력해 주세요.';
      case ExtractFailureReason.ambiguous:
        return '가격이 여러 개라 확실하지 않아요. 가격을 직접 입력해 주세요.';
      default:
        return info.needsManualPrice ? '가격을 직접 입력해 주세요' : 'AI로 읽음';
    }
  }

  /// 카드의 사진 자리. 직접 찍은 옷 사진이 있으면 그 사진(저장하면 대표 사진이 됨), 없으면 쇼핑몰 사진,
  /// 직접 기록 중인데 사진이 없으면 눌러서 옷 사진을 넣는 자리.
  Widget _imageSlot(ParsedProductInfo info) {
    const size = 72.0;
    final radius = BorderRadius.circular(DiaryTheme.radius);
    final photo = clothesPhoto;
    if (photo != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(photo, width: size, height: size, fit: BoxFit.cover),
      );
    }
    if (info.image.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          info.image,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(width: size, height: size, color: DiaryColors.grid),
        ),
      );
    }
    if (!manualMode) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: '옷 사진 넣기',
      child: InkWell(
        borderRadius: radius,
        onTap: saving ? null : _pickClothesPhoto,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: DiaryColors.paper,
            borderRadius: radius,
            border: Border.all(color: DiaryColors.lineStrong),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_a_photo_outlined, color: DiaryColors.inkMuted, size: 22),
              const SizedBox(height: 2),
              Text('옷 사진', style: DiaryTheme.body(11, color: DiaryColors.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final lists = store.tabs.where((t) => t.id != 'all').toList();

    return Scaffold(
      backgroundColor: DiaryColors.paper,
      appBar: AppBar(
        title: const Text('공유 담기'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DiaryGridPaper(
            padding: EdgeInsets.zero,
            child: ListView(
              children: [
                // 한 줄로 — 좁은 화면에서는 줄바꿈 대신 글자를 살짝 줄인다.
                OneLineText(
                  '다른 앱에서 공유한 링크를 wishkit 카드로 정리해요',
                  style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '상품 URL 또는 공유 텍스트',
                    filled: true,
                    fillColor: DiaryColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(DiaryTheme.radius),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: loading || identifying ? null : _parse,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 읽는 동안은 버튼 글자 왼쪽에 도는 표시.
                DiaryButton(
                  label: loading ? '상품 페이지를 읽는 중...' : '상품 읽기',
                  filled: true,
                  loading: loading,
                  onPressed: loading || identifying ? () {} : _parse,
                ),
                const SizedBox(height: 8),
                DiaryButton(
                  label: identifying
                      ? '태그를 읽고 판매 페이지를 찾는 중... (최대 30초)'
                      : '태그 사진으로 찾기',
                  icon: Icons.photo_camera_outlined,
                  loading: identifying,
                  onPressed: loading || identifying ? null : _pickTagPhoto,
                ),
                // 아직 아무것도 못 읽었거나 링크 읽기가 실패했을 때만 — 읽은 쇼핑몰 정보를 덮어쓰지 않게.
                if (!manualMode &&
                    !identifying &&
                    (parsed == null || parsed!.extractFailureReason != null)) ...[
                  const SizedBox(height: 8),
                  // 링크도 없고 태그로도 못 찾을 때(오프라인 매장 등) — 옷 사진·이름·가격만으로 기록.
                  DiaryButton(
                    label: '사진으로 직접 기록하기',
                    icon: Icons.edit_note_outlined,
                    onPressed: loading ? null : _startManual,
                  ),
                ],
                // 태그 찾기를 기다리는 동안만 큰 광고(최대 화면 높이의 70%). 버튼 아래에만 두고
                // 겹치지 않게, 버튼과 충분히 띄운다(실수 클릭 방지).
                if (identifying) ...[
                  const SizedBox(height: 28),
                  const TagSearchBannerAd(),
                ],
                if (tagResult != null &&
                    tagResult!.status != TagIdentifyStatus.notATag) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DiaryColors.band,
                      borderRadius: BorderRadius.circular(DiaryTheme.radius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tagPhoto != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(DiaryTheme.radius),
                            child: Image.memory(
                              tagPhoto!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in _tagResultLines(tagResult!))
                                Text(
                                  line,
                                  style: DiaryTheme.body(
                                    12,
                                    color: DiaryColors.inkMuted,
                                  ),
                                ),
                              if (tagPhoto != null)
                                Text(
                                  '저장하면 태그 사진도 함께 저장돼요 (나만 볼 수 있어요)',
                                  style: DiaryTheme.body(
                                    11,
                                    color: DiaryColors.inkSoft,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tagConfirmPending) ...[
                    const SizedBox(height: 8),
                    DiaryButton(
                      label: '링크 열어서 확인하기',
                      icon: Icons.open_in_new,
                      onPressed: loading ? null : _openTagMatch,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DiaryButton(
                            label: '맞아요',
                            filled: true,
                            color: DiaryColors.folderMint,
                            icon: Icons.check,
                            onPressed: loading
                                ? null
                                : () => _answerTagConfirm(same: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DiaryButton(
                            label: '다른 상품이에요',
                            icon: Icons.close,
                            onPressed: loading
                                ? null
                                : () => _answerTagConfirm(same: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: DiaryTheme.body(12, color: DiaryColors.pin),
                  ),
                ],
                if (parsed != null) ...[
                  const SizedBox(height: 16),
                  WhiteProductCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _imageSlot(parsed!),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                parsed!.platform,
                                style: DiaryTheme.body(
                                  12,
                                  color: DiaryColors.inkMuted,
                                ),
                              ),
                              Text(
                                _statusText(parsed!),
                                style: DiaryTheme.body(
                                  11,
                                  color: DiaryColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (clothesPhoto != null || manualMode) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DiaryButton(
                            label: clothesPhoto == null ? '옷 사진 넣기' : '옷 사진 바꾸기',
                            icon: Icons.checkroom_outlined,
                            onPressed: saving ? null : _pickClothesPhoto,
                          ),
                        ),
                        if (clothesPhoto != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: DiaryButton(
                              label: '옷 사진 빼기',
                              icon: Icons.close,
                              onPressed: saving ? null : _removeClothesPhoto,
                            ),
                          ),
                        ],
                      ],
                    ),
                    // 직접 기록 중인데 아직 태그를 안 찍었으면 — 찍으면 이름·가격을 읽어 채우고, 태그 사진도 남는다.
                    if (manualMode && tagPhoto == null) ...[
                      const SizedBox(height: 8),
                      DiaryButton(
                        label: identifying ? '태그를 읽는 중...' : '태그 사진 넣기 (이름·가격 자동 입력)',
                        icon: Icons.sell_outlined,
                        loading: identifying,
                        onPressed: identifying || saving ? null : _pickTagPhoto,
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '상품명',
                      filled: true,
                      fillColor: DiaryColors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: parsed!.needsManualPrice
                          ? '판매가 (직접 입력, 원)'
                          : '기본 판매가 (쿠폰·옵션 제외, 원)',
                      filled: true,
                      fillColor: DiaryColors.white,
                    ),
                  ),
                  // 판매 페이지에서 가격을 못 읽었을 때, 태그에서 읽은 가격으로 한 번에 채울 수 있게.
                  // 태그 가격은 정가라 판매가와 다를 수 있어서 자동으로 넣지 않고 사용자가 고른다.
                  if (tagResult?.tagPrice != null)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: priceCtrl,
                      builder: (context, value, _) {
                        if (value.text.trim().isNotEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: DiaryButton(
                            label:
                                '태그 가격 ${formatWon(tagResult!.tagPrice!)}으로 채우기',
                            icon: Icons.sell_outlined,
                            onPressed: () =>
                                priceCtrl.text = '${tagResult!.tagPrice!}',
                          ),
                        );
                      },
                    ),
                  if (parsed!.originalPrice != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '정가 ${formatWon(parsed!.originalPrice!)} · '
                      '판매가 ${formatWon(parsed!.price)}',
                      style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // 제대로 읽었으면 가격 기준 안내, 못 읽었으면 직접 입력 안내.
                  if (manualMode)
                    Text(
                      '매장에서 본 상품을 직접 기록해요. 가격이 비어 있으면 직접 입력해 주세요.',
                      style: DiaryTheme.body(11, color: DiaryColors.inkMuted),
                    )
                  else if (parsed!.extractFailureReason != null ||
                      parsed!.needsManualPrice)
                    Text(
                      '상품 정보를 읽지 못했어요. 상품명과 판매가를 직접 입력해 주세요.',
                      style: DiaryTheme.body(12, color: DiaryColors.pin),
                    )
                  else
                    Text(
                      '쿠폰을 제외한 기본 판매가예요. 옵션에 따라 가격이 달라질 수 있어요.',
                      style: DiaryTheme.body(11, color: DiaryColors.inkMuted),
                    ),
                  if (!manualMode &&
                      parsed!.missingFields.isNotEmpty &&
                      parsed!.extractFailureReason == null &&
                      !parsed!.needsManualPrice) ...[
                    const SizedBox(height: 8),
                    Text(
                      '보완 필요: ${parsed!.missingFields.join(', ')}',
                      style: DiaryTheme.body(12, color: DiaryColors.pin),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    '어느 폴더로 보낼까요?',
                    style: DiaryTheme.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tab in lists)
                        ChoiceChip(
                          label: Text(
                            tab.name,
                            style: DiaryTheme.ui(
                              14,
                              weight: FontWeight.w600,
                              color: selectedListId == tab.id
                                  ? DiaryColors.white
                                  : DiaryColors.ink,
                            ),
                          ),
                          showCheckmark: false,
                          selected: selectedListId == tab.id,
                          selectedColor: DiaryColors.ink,
                          // 다시 누르면 선택을 풀고 '전체'에만 저장.
                          onSelected: (_) => setState(
                            () => selectedListId =
                                selectedListId == tab.id ? 'all' : tab.id,
                          ),
                        ),
                      // 마이페이지와 같은 "폴더 추가" — 만들면 바로 그 폴더를 고른다.
                      ActionChip(
                        avatar: const Icon(
                          Icons.add,
                          size: 16,
                          color: DiaryColors.inkMuted,
                        ),
                        label: Text(
                          '폴더 추가',
                          style: DiaryTheme.ui(
                            14,
                            weight: FontWeight.w600,
                            color: DiaryColors.inkMuted,
                          ),
                        ),
                        side: const BorderSide(color: DiaryColors.lineStrong),
                        backgroundColor: DiaryColors.paper,
                        onPressed: () async {
                          final created = await showAddFolderDialog(
                            context,
                            store,
                          );
                          if (created != null && mounted) {
                            setState(() => selectedListId = created.id);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "폴더를 고르지 않으면 '전체' 폴더에만 저장돼요.",
                    style: DiaryTheme.body(11, color: DiaryColors.inkMuted),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '고민하는 이유',
                    style: DiaryTheme.body(14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: memoCtrl,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: '이 상품을 고민하는 이유를 남겨보세요',
                      filled: true,
                      fillColor: DiaryColors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DiaryButton(
                    label: saving ? '저장하는 중...' : '저장하기',
                    filled: true,
                    onPressed: saving ? null : _save,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
