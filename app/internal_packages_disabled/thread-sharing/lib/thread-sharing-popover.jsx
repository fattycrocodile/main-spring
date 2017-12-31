/* eslint jsx-a11y/tabindex-no-positive: 0 */
import classnames from 'classnames';
import {
  Rx,
  React,
  ReactDOM,
  PropTypes,
  Actions,
  NylasAPIHelpers,
  Thread,
  DatabaseStore,
  SyncbackMetadataTask,
} from 'mailspring-exports';
import { RetinaImg } from 'mailspring-component-kit';

import CopyButton from './copy-button';
import { PLUGIN_ID, PLUGIN_NAME, PLUGIN_URL } from './thread-sharing-constants';

function isShared(thread) {
  const metadata = thread.metadataForPluginId(PLUGIN_ID) || {};
  return metadata.shared || false;
}

export default class ThreadSharingPopover extends React.Component {
  static propTypes = {
    thread: PropTypes.object,
    accountId: PropTypes.string,
  };

  constructor(props) {
    super(props);
    this.state = {
      shared: isShared(props.thread),
      saving: false,
    };
    this._disposable = { dispose: () => {} };
  }

  componentDidMount() {
    const { thread } = this.props;
    this._mounted = true;
    this._disposable = Rx.Observable
      .fromQuery(DatabaseStore.find(Thread, thread.id))
      .subscribe(t => this.setState({ shared: isShared(t) }));
  }

  componentDidUpdate() {
    ReactDOM.findDOMNode(this).focus();
  }

  componentWillUnmount() {
    this._disposable.dispose();
    this._mounted = false;
  }

  _onToggleShared = async () => {
    const { thread } = this.props;
    const { shared } = this.state;

    this.setState({ saving: true });

    try {
      if (!this._mounted) {
        return;
      }

      Actions.queueTask(
        SyncbackMetadataTask.forSaving({
          model: thread,
          pluginId: PLUGIN_ID,
          value: { shared: !shared },
        })
      );
    } catch (error) {
      AppEnv.reportError(error);
      AppEnv.showErrorDialog(
        `Sorry, we were unable to update your sharing settings.\n\n${error.message}`
      );
    }

    if (!this._mounted) {
      return;
    }
    this.setState({ saving: false });
  };

  _onClickInput = event => {
    const input = event.target;
    input.select();
  };

  render() {
    const { thread, accountId } = this.props;
    const { shared, saving } = this.state;

    const url = `${PLUGIN_URL}/thread/${accountId}/${thread.id}`;
    const shareMessage = shared
      ? 'Anyone with the link can read the thread'
      : 'Sharing is disabled';
    const classes = classnames({
      'thread-sharing-popover': true,
      disabled: !shared,
    });

    const control = saving ? (
      <RetinaImg
        style={{ width: 14, height: 14, marginBottom: 3, marginRight: 4 }}
        name="inline-loading-spinner.gif"
        mode={RetinaImg.Mode.ContentPreserve}
      />
    ) : (
      <input type="checkbox" id="shareCheckbox" checked={shared} onChange={this._onToggleShared} />
    );

    // tabIndex is necessary for the popover's onBlur events to work properly
    return (
      <div tabIndex="1" className={classes}>
        <div className="share-toggle">
          <label htmlFor="shareCheckbox">
            {control}
            Share this thread
          </label>
        </div>
        <div className="share-input">
          <input
            ref="urlInput"
            id="urlInput"
            type="text"
            value={url}
            readOnly
            disabled={!shared}
            onClick={this._onClickInput}
          />
        </div>
        <div className={`share-controls`}>
          <div className="share-message">{shareMessage}</div>
          <button href={url} className="btn" disabled={!shared}>
            Open in browser
          </button>
          <CopyButton className="btn" disabled={!shared} copyValue={url} btnLabel="Copy link" />
        </div>
      </div>
    );
  }
}
