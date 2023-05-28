<?php
$file = file_get_contents($_GET['url']);

// 用正则表达式提取group_title和m3u8链接
preg_match_all('/#EXTINF:-1.*?group-title="(.*?)".*?,(.*?)\n(.*?)\n/s', $file, $matches, PREG_SET_ORDER);

$result = array();

foreach ($matches as $match) {
    $group_title = $match[1];
    $url = $match[3];
    $channel_name = $match[2];
    $result[$group_title][] = $channel_name . ',' . $url;
}

$line_f = "\n";

// 输出处理后的结果
if (isset($_SERVER["HTTP_USER_AGENT"]) && strpos($_SERVER["HTTP_USER_AGENT"], "Mozilla") !== false) {
    // 如果是浏览器访问，将 "\n" 替换为 "<br>" 输出
    $line_f = "<br>"; 
}

// 输出结果
foreach ($result as $group_title => $channels) {
    echo $group_title . ',#genre#' . $line_f;
    foreach ($channels as $channel) {
        echo $channel . $line_f;
    }
    echo $line_f;
}
?>
