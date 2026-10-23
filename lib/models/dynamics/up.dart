// 安全转换为 int?，防止 API 返回 String 类型导致类型错误
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  return null;
}

class FollowUpModel {
  FollowUpModel({
    this.liveUsers,
    this.upList,
    this.liveList,
    this.myInfo,
  });

  LiveUsers? liveUsers;
  List<UpItem>? upList;
  List<LiveUserItem>? liveList;
  MyInfo? myInfo;

  FollowUpModel.fromJson(Map<String, dynamic> json) {
    liveUsers = json['live_users'] != null
        ? LiveUsers.fromJson(json['live_users'])
        : null;
    liveList = json['live_users'] != null
        ? json['live_users']['items']
            .map<LiveUserItem>((e) => LiveUserItem.fromJson(e))
            .toList()
        : [];
    upList = json['up_list'] != null
        ? json['up_list'].map<UpItem>((e) => UpItem.fromJson(e)).toList()
        : [];
    myInfo = json['my_info'] != null ? MyInfo.fromJson(json['my_info']) : null;
  }
}

class LiveUsers {
  LiveUsers({
    this.count,
    this.group,
    this.items,
  });

  int? count;
  String? group;
  List<LiveUserItem>? items;

  LiveUsers.fromJson(Map<String, dynamic> json) {
    count = _toInt(json['count']);
    group = json['group'];
    items = json['items']
        .map<LiveUserItem>((e) => LiveUserItem.fromJson(e))
        .toList();
  }
}

class LiveUserItem {
  LiveUserItem({
    this.face,
    this.isReserveRecall,
    this.jumpUrl,
    this.mid,
    this.roomId,
    this.title,
    this.uname,
  });

  String? face;
  bool? isReserveRecall;
  String? jumpUrl;
  int? mid;
  int? roomId;
  String? title;
  String? uname;
  bool hasUpdate = false;
  String type = 'live';

  LiveUserItem.fromJson(Map<String, dynamic> json) {
    face = json['face'];
    isReserveRecall = json['is_reserve_recall'];
    jumpUrl = json['jump_url'];
    mid = _toInt(json['mid']);
    roomId = _toInt(json['room_id']);
    title = json['title'];
    uname = json['uname'];
  }
}

class UpItem {
  UpItem({
    this.face,
    this.hasUpdate,
    this.isReserveRecall,
    this.mid,
    this.uname,
  });

  String? face;
  bool? hasUpdate;
  bool? isReserveRecall;
  int? mid;
  String? uname;
  String type = 'up';

  UpItem.fromJson(Map<String, dynamic> json) {
    face = json['face'];
    hasUpdate = json['has_update'];
    isReserveRecall = json['is_reserve_recall'];
    mid = _toInt(json['mid']);
    uname = json['uname'];
  }
}

class MyInfo {
  MyInfo({
    this.face,
    this.mid,
    this.name,
  });

  String? face;
  int? mid;
  String? name;

  MyInfo.fromJson(Map<String, dynamic> json) {
    face = json['face'];
    mid = _toInt(json['mid']);
    name = json['name'];
  }
}
